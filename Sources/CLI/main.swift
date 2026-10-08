import Foundation

// CLI de test : transcrit un fichier audio avec toute la chaîne (Whisper + nettoyage + dictionnaire).
// Usage : dictee-cli <fichier.wav> [--lang fr|en|auto] [--raw] [--repeat N] [--app bundle.id]

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    print("usage: dictee-cli <audio.wav> [--lang auto] [--raw] [--repeat N] [--app bundle.id] [--model chemin.bin]")
    exit(2)
}
func take(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
let lang = take("--lang")
let repeatCount = Int(take("--repeat") ?? "1") ?? 1
let appBundle = take("--app")
let modelOverride = take("--model")
let showRaw = args.contains("--raw"); args.removeAll { $0 == "--raw" }
let file = args.first.map { URL(fileURLWithPath: $0) }

guard let file = file else { print("fichier audio manquant"); exit(2) }

Paths.ensureDirs()
var config = Config.load()
if let lang = lang { config.language = lang }
let modelPath = modelOverride ?? Paths.modelsDir.appendingPathComponent(config.model).path
guard FileManager.default.fileExists(atPath: modelPath) else {
    print("Modèle introuvable : \(modelPath)\nLance ./install.sh (ou scripts/download-model.sh) d'abord.")
    exit(1)
}

do {
    let t0 = Date()
    let engine = try WhisperEngine(modelPath: modelPath)
    print(String(format: "modèle chargé en %.2f s : %@", Date().timeIntervalSince(t0), (modelPath as NSString).lastPathComponent))
    let samples = try AudioFile.loadMono16k(file)
    let pipeline = DictationPipeline(config: config, engine: engine)
    for i in 1...max(1, repeatCount) {
        let out = pipeline.process(samples: samples, appBundle: appBundle)
        if showRaw { print("brut [\(out.language)] : \(out.raw)") }
        print(String(format: "#%d  audio %.1f s → whisper %.2f s, total %.2f s [%@]", i, out.audioSeconds, out.whisperSeconds, out.totalSeconds, out.language))
        print(out.text)
    }
} catch {
    print("Erreur : \(error.localizedDescription)")
    exit(1)
}
