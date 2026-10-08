import Foundation

/// Chaîne complète : audio → Whisper → snippets → dictionnaire → nettoyage → (LLM optionnel) → style par app.
public final class DictationPipeline {
    public private(set) var config: Config
    public private(set) var dictionary: PersonalDictionary
    public private(set) var snippets: Snippets
    public private(set) var learned: LearnedStore
    public let engine: WhisperEngine
    private let lock = NSLock()

    public struct Output {
        public let raw: String
        public let text: String
        public let language: String
        public let whisperSeconds: Double
        public let totalSeconds: Double
        public let audioSeconds: Double
    }

    public init(config: Config, engine: WhisperEngine) {
        self.config = config
        self.engine = engine
        dictionary = PersonalDictionary.load()
        snippets = Snippets.load()
        learned = LearnedStore.load()
    }

    /// Recharge config, dictionnaire et snippets (après édition des fichiers).
    public func reload() {
        lock.lock(); defer { lock.unlock() }
        config = Config.load()
        dictionary = PersonalDictionary.load()
        snippets = Snippets.load()
        learned = LearnedStore.load()
        Log.info("Config rechargée : \(dictionary.words.count) mots, \(dictionary.replacements.count + dictionary.learned.count) règles, \(snippets.map.count) snippets")
    }

    public func process(samples: [Float], appBundle: String?) -> Output {
        let t0 = Date()
        var opts = WhisperEngine.Options()
        opts.language = config.language
        opts.prompt = dictionary.initialPrompt()
        opts.threads = config.threads
        let r = engine.transcribe(samples, options: opts)
        let text = postProcess(raw: r.text, language: r.language, appBundle: appBundle)
        return Output(raw: r.text, text: text, language: r.language, whisperSeconds: r.seconds,
                      totalSeconds: Date().timeIntervalSince(t0), audioSeconds: r.audioSeconds)
    }

    /// Partie texte seule (testable sans audio).
    public func postProcess(raw: String, language: String, appBundle: String?) -> String {
        lock.lock(); defer { lock.unlock() }
        let lang = language.isEmpty ? "fr" : language
        var t = snippets.apply(to: raw)
        let snippetOnly = snippets.map.contains { TextUtil.key($0.key) == TextUtil.key(raw) }
        if snippetOnly { return t }
        t = dictionary.apply(to: t)
        t = Cleaner(config: config.cleaning).clean(t, lang: lang)
        if config.llm.enabled, !t.isEmpty {
            if let polished = LLMPolish.polish(t, lang: lang, config: config.llm) { t = polished }
        }
        t = dictionary.apply(to: t)   // au cas où le LLM aurait "corrigé" un nom propre
        return Styler.apply(t, style: config.style(for: appBundle), protectedKeys: dictionary.knownKeys)
    }

    /// Apprentissage : compare le texte collé et le texte relu ; retourne les règles promues.
    public func learn(pasted: String, observed: String) -> [Correction] {
        lock.lock(); defer { lock.unlock() }
        guard config.learning.enabled else { return [] }
        let corrections = Learner.corrections(pasted: pasted, observed: observed, dictionary: dictionary)
        guard !corrections.isEmpty else { return [] }
        let promoted = Learner.learn(corrections, store: &learned, dictionary: &dictionary, threshold: config.learning.threshold)
        do { try learned.save(); if !promoted.isEmpty { try dictionary.save() } }
        catch { Log.error("Sauvegarde apprentissage : \(error)") }
        Log.info("Apprentissage : \(corrections.count) correction(s) vue(s), \(promoted.count) promue(s) \(promoted.map { "\($0.original)→\($0.corrected)" })")
        return promoted
    }

    public func addWord(_ w: String) {
        lock.lock(); defer { lock.unlock() }
        guard !dictionary.hasWord(w) else { return }
        dictionary.words.append(w); try? dictionary.save()
    }
}

/// Passe optionnelle par l'API Anthropic (désactivée par défaut, jamais requise).
/// Clé lue dans le fichier `llm.env_file` (ANTHROPIC_API_KEY=...) ou dans l'environnement.
public enum LLMPolish {
    static func apiKey(_ config: LLMConfig) -> String? {
        if let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty { return k }
        guard let content = try? String(contentsOf: Paths.expand(config.envFile), encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("ANTHROPIC_API_KEY") , let eq = l.firstIndex(of: "=") else { continue }
            var v = String(l[l.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("export ") { v = String(v.dropFirst(7)) }
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !v.isEmpty { return v }
        }
        return nil
    }

    public static func polish(_ text: String, lang: String, config: LLMConfig) -> String? {
        guard let key = apiKey(config) else { Log.warn("LLM activé mais aucune clé ANTHROPIC_API_KEY trouvée (\(config.envFile))"); return nil }
        let system = """
        You clean up dictated text. Fix punctuation, capitalization, obvious speech-recognition errors and remove hesitations. \
        Keep the language (\(lang)), the meaning, the wording and every proper noun exactly as given. Never add, answer or comment. \
        Return only the corrected text.
        """
        let body: [String: Any] = [
            "model": config.model, "max_tokens": 1024, "system": system,
            "messages": [["role": "user", "content": text]],
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = config.timeoutSeconds
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let sem = DispatchSemaphore(value: 0)
        var result: String? = nil
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            guard let data = data, err == nil else { Log.warn("LLM : \(err?.localizedDescription ?? "?")"); return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let e = json["error"] as? [String: Any] { Log.warn("LLM : \(e["message"] ?? e)"); return }
            guard let content = json["content"] as? [[String: Any]] else { return }
            let out = content.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty { result = out }
        }.resume()
        _ = sem.wait(timeout: .now() + config.timeoutSeconds + 1)
        return result
    }
}

/// Historique des dernières dictées (~/.config/dictee/history.json).
public struct HistoryEntry: Codable, Equatable {
    public var date: String
    public var text: String
    public var raw: String
    public var app: String?
    public var language: String
    public var audioSeconds: Double
    public var latencySeconds: Double
}

public struct History {
    public private(set) var entries: [HistoryEntry] = []
    public var limit: Int
    public init(limit: Int = 50) { self.limit = limit }

    public static func load(limit: Int) -> History {
        var h = History(limit: limit)
        if let data = try? Data(contentsOf: Paths.historyFile), let e = try? JSONDecoder().decode([HistoryEntry].self, from: data) { h.entries = e }
        return h
    }
    public mutating func add(_ e: HistoryEntry) {
        entries.insert(e, at: 0)
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try? enc.encode(entries).write(to: Paths.historyFile, options: .atomic)
    }
}
