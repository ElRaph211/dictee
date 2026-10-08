import Foundation
import CWhisper

/// Moteur de transcription : whisper.cpp (Metal) chargé une fois et gardé en mémoire.
public final class WhisperEngine {
    public struct Result {
        public let text: String
        public let language: String
        public let seconds: Double     // durée de traitement
        public let audioSeconds: Double
    }
    public struct Options {
        public var language: String = "auto"      // "auto", "fr", "en"...
        public var prompt: String = ""
        public var threads: Int = 0               // 0 = auto
        public var beamSize: Int = 5
        public var dynamicAudioCtx: Bool = true   // réduit l'encodeur pour les dictées courtes (plus rapide)
        public init() {}
    }

    private var ctx: OpaquePointer
    private let lock = NSLock()
    public let modelPath: String

    public init(modelPath: String, useGPU: Bool = true) throws {
        Self.installLogHook()
        var cp = whisper_context_default_params()
        cp.use_gpu = useGPU
        cp.flash_attn = true
        guard let c = whisper_init_from_file_with_params(modelPath, cp) else {
            throw NSError(domain: "Dictee", code: 1, userInfo: [NSLocalizedDescriptionKey: "Impossible de charger le modèle \(modelPath)"])
        }
        ctx = c; self.modelPath = modelPath
    }
    deinit { whisper_free(ctx) }

    private static var logHookInstalled = false
    private static func installLogHook() {
        guard !logHookInstalled else { return }; logHookInstalled = true
        whisper_log_set({ level, text, _ in
            guard let text = text else { return }
            let s = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return }
            if level == GGML_LOG_LEVEL_ERROR { Log.error("whisper: \(s)") }
            else if level == GGML_LOG_LEVEL_WARN { Log.warn("whisper: \(s)") }
            // les INFO (chargement, métal) sont volontairement tus : trop verbeux
        }, nil)
    }

    static func audioCtx(forSeconds s: Double) -> Int32 { WhisperEngineCtx.audioCtx(s) }

    /// `samples` : PCM float32 mono 16 kHz.
    public func transcribe(_ samples: [Float], options: Options = Options()) -> Result {
        lock.lock(); defer { lock.unlock() }
        let t0 = Date()
        let audioSeconds = Double(samples.count) / 16000.0
        var p = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        p.beam_search.beam_size = Int32(max(1, options.beamSize))
        p.greedy.best_of = Int32(max(1, options.beamSize))
        p.n_threads = Int32(options.threads > 0 ? options.threads : min(4, max(1, ProcessInfo.processInfo.activeProcessorCount - 2)))
        p.print_progress = false; p.print_realtime = false; p.print_special = false; p.print_timestamps = false
        // Garde-fous anti-boucle (phrase répétée N fois) :
        p.no_timestamps = false          // les timestamps bornent le décodage à la fin de l'audio
        p.single_segment = false
        p.suppress_blank = true
        p.suppress_nst = true
        p.no_context = true              // aucune dictée précédente ne conditionne la suivante
        p.temperature = 0
        p.temperature_inc = 0.2          // repli à température croissante si le décodage dégénère
        p.entropy_thold = 2.4            // texte trop répétitif → repli
        p.logprob_thold = -1.0
        p.no_speech_thold = 0.6
        p.max_tokens = Int32(min(440, 6 * Int(audioSeconds.rounded(.up)) + 32))   // parole ≈ 3 tokens/s : coupe une boucle
        if options.dynamicAudioCtx && audioSeconds < 24 { p.audio_ctx = Self.audioCtx(forSeconds: audioSeconds) }

        let lang = strdup(options.language.isEmpty ? "auto" : options.language)
        let prompt = options.prompt.isEmpty ? nil : strdup(options.prompt)
        defer { free(lang); if let prompt = prompt { free(prompt) } }
        p.language = UnsafePointer(lang)
        p.detect_language = false
        if let prompt = prompt { p.initial_prompt = UnsafePointer(prompt) }

        // whisper.cpp exige au moins ~1 s d'audio : on complète par du silence
        var pcm = samples
        if pcm.count < 16000 * 11 / 10 { pcm.append(contentsOf: [Float](repeating: 0, count: 16000 * 11 / 10 - pcm.count)) }

        let rc = pcm.withUnsafeBufferPointer { whisper_full(ctx, p, $0.baseAddress, Int32($0.count)) }
        guard rc == 0 else {
            Log.error("whisper_full a échoué (code \(rc))")
            return Result(text: "", language: "", seconds: Date().timeIntervalSince(t0), audioSeconds: audioSeconds)
        }
        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let s = whisper_full_get_segment_text(ctx, i) { text += String(cString: s) }
        }
        let langId = whisper_full_lang_id(ctx)
        let language = langId >= 0 ? String(cString: whisper_lang_str(langId)) : options.language
        return Result(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: language,
                      seconds: Date().timeIntervalSince(t0), audioSeconds: audioSeconds)
    }
}
