import Foundation

/// Tous les chemins de l'outil. Aucun chemin en dur vers un utilisateur :
/// tout part de $HOME (ou de la variable DICTEE_HOME pour les tests).
public enum Paths {
    public static var home: URL {
        if let override = ProcessInfo.processInfo.environment["DICTEE_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// ~/.config/dictee : config.json, dictionary.json, snippets.json, learned.json, history.json
    public static var configDir: URL { home.appendingPathComponent(".config/dictee", isDirectory: true) }
    public static var configFile: URL { configDir.appendingPathComponent("config.json") }
    public static var dictionaryFile: URL { configDir.appendingPathComponent("dictionary.json") }
    public static var snippetsFile: URL { configDir.appendingPathComponent("snippets.json") }
    public static var learnedFile: URL { configDir.appendingPathComponent("learned.json") }
    public static var historyFile: URL { configDir.appendingPathComponent("history.json") }

    /// ~/Library/Application Support/Dictee/models : les modèles Whisper (ggml)
    public static var modelsDir: URL {
        home.appendingPathComponent("Library/Application Support/Dictee/models", isDirectory: true)
    }

    /// ~/Library/Logs/Dictee
    public static var logsDir: URL { home.appendingPathComponent("Library/Logs/Dictee", isDirectory: true) }

    public static func ensureDirs() {
        for d in [configDir, modelsDir, logsDir] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    /// Développe "~" et les variables d'environnement d'un chemin de config.
    public static func expand(_ path: String) -> URL {
        var p = path
        if p.hasPrefix("~") { p = home.path + p.dropFirst() }
        return URL(fileURLWithPath: p)
    }
}
