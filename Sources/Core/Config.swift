import Foundation

/// Style de sortie par application (clé = bundle id, "default" = partout ailleurs).
public struct AppStyle: Codable, Equatable {
    public var capitalizeFirst: Bool?        // majuscule en début de dictée (défaut true)
    public var trailingPunctuation: Bool?    // ajouter un point final si absent (défaut true)
    public var trailingSpace: Bool?          // espace après le texte collé (défaut false)
    public var pasteMethod: String?          // "paste" (Cmd+V) ou "type" (frappe, plus lent)

    enum CodingKeys: String, CodingKey {
        case capitalizeFirst = "capitalize_first"
        case trailingPunctuation = "trailing_punctuation"
        case trailingSpace = "trailing_space"
        case pasteMethod = "paste_method"
    }
    public init(capitalizeFirst: Bool? = nil, trailingPunctuation: Bool? = nil, trailingSpace: Bool? = nil, pasteMethod: String? = nil) {
        self.capitalizeFirst = capitalizeFirst; self.trailingPunctuation = trailingPunctuation
        self.trailingSpace = trailingSpace; self.pasteMethod = pasteMethod
    }
    public func merged(over base: AppStyle) -> AppStyle {
        AppStyle(capitalizeFirst: capitalizeFirst ?? base.capitalizeFirst,
                 trailingPunctuation: trailingPunctuation ?? base.trailingPunctuation,
                 trailingSpace: trailingSpace ?? base.trailingSpace,
                 pasteMethod: pasteMethod ?? base.pasteMethod)
    }
}

public struct LLMConfig: Codable, Equatable {
    public var enabled: Bool = false
    public var model: String = "claude-haiku-5-5"
    public var envFile: String = "~/.config/dictee/anthropic.env"   // contient ANTHROPIC_API_KEY=...
    public var timeoutSeconds: Double = 6
    enum CodingKeys: String, CodingKey {
        case enabled, model
        case envFile = "env_file"
        case timeoutSeconds = "timeout_seconds"
    }
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "claude-haiku-5-5"
        envFile = try c.decodeIfPresent(String.self, forKey: .envFile) ?? "~/.config/dictee/anthropic.env"
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 6
    }
}

public struct LearningConfig: Codable, Equatable {
    public var enabled: Bool = true
    public var threshold: Int = 2          // nb de fois qu'une même correction doit être vue avant d'entrer au dictionnaire
    public var delaySeconds: Double = 8    // délai avant relecture du champ via Accessibilité
    enum CodingKeys: String, CodingKey {
        case enabled, threshold
        case delaySeconds = "delay_seconds"
    }
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        threshold = try c.decodeIfPresent(Int.self, forKey: .threshold) ?? 2
        delaySeconds = try c.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? 8
    }
}

public struct CleaningConfig: Codable, Equatable {
    public var removeFillers: Bool = true
    public var selfCorrections: Bool = true
    public var spokenPunctuation: Bool = true          // "point d'interrogation", "nouvelle ligne"...
    public var spokenPunctuationExtended: Bool = false // "virgule", "point", "deux points" (plus risqué)
    public var lists: Bool = true                      // premièrement / deuxièmement → 1. 2.
    public var dropTrailingQuoi: Bool = true           // "... c'est trop long quoi." → "... c'est trop long."
    enum CodingKeys: String, CodingKey {
        case removeFillers = "remove_fillers"
        case selfCorrections = "self_corrections"
        case spokenPunctuation = "spoken_punctuation"
        case spokenPunctuationExtended = "spoken_punctuation_extended"
        case lists
        case dropTrailingQuoi = "drop_trailing_quoi"
    }
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        removeFillers = try c.decodeIfPresent(Bool.self, forKey: .removeFillers) ?? true
        selfCorrections = try c.decodeIfPresent(Bool.self, forKey: .selfCorrections) ?? true
        spokenPunctuation = try c.decodeIfPresent(Bool.self, forKey: .spokenPunctuation) ?? true
        spokenPunctuationExtended = try c.decodeIfPresent(Bool.self, forKey: .spokenPunctuationExtended) ?? false
        lists = try c.decodeIfPresent(Bool.self, forKey: .lists) ?? true
        dropTrailingQuoi = try c.decodeIfPresent(Bool.self, forKey: .dropTrailingQuoi) ?? true
    }
}

public struct Config: Codable, Equatable {
    public var model: String = "ggml-large-v3-turbo-q5_0.bin"   // fichier dans ~/Library/Application Support/Dictee/models
    public var language: String = "auto"                     // "auto", "fr", "en"
    public var threads: Int = 0                              // 0 = auto
    public var sounds: Bool = true
    public var micName: String? = nil                        // nil = micro par défaut du système
    public var doubleTapMs: Int = 400                        // délai max entre deux tap fn pour le mode mains libres
    public var maxHoldAsTapMs: Int = 300                     // en dessous, un appui est un "tap"
    public var historySize: Int = 50
    public var llm = LLMConfig()
    public var learning = LearningConfig()
    public var cleaning = CleaningConfig()
    public var appStyles: [String: AppStyle] = [:]

    enum CodingKeys: String, CodingKey {
        case model, language, threads, sounds
        case micName = "mic_name"
        case doubleTapMs = "double_tap_ms"
        case maxHoldAsTapMs = "max_hold_as_tap_ms"
        case historySize = "history_size"
        case llm, learning, cleaning
        case appStyles = "app_styles"
    }
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "ggml-large-v3-turbo-q5_0.bin"
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        threads = try c.decodeIfPresent(Int.self, forKey: .threads) ?? 0
        sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? true
        micName = try c.decodeIfPresent(String.self, forKey: .micName)
        doubleTapMs = try c.decodeIfPresent(Int.self, forKey: .doubleTapMs) ?? 400
        maxHoldAsTapMs = try c.decodeIfPresent(Int.self, forKey: .maxHoldAsTapMs) ?? 300
        historySize = try c.decodeIfPresent(Int.self, forKey: .historySize) ?? 50
        llm = try c.decodeIfPresent(LLMConfig.self, forKey: .llm) ?? LLMConfig()
        learning = try c.decodeIfPresent(LearningConfig.self, forKey: .learning) ?? LearningConfig()
        cleaning = try c.decodeIfPresent(CleaningConfig.self, forKey: .cleaning) ?? CleaningConfig()
        appStyles = try c.decodeIfPresent([String: AppStyle].self, forKey: .appStyles) ?? [:]
    }

    /// Style effectif pour une app : "default" puis la clé exacte du bundle id.
    public func style(for bundleId: String?) -> AppStyle {
        let base = AppStyle(capitalizeFirst: true, trailingPunctuation: true, trailingSpace: false, pasteMethod: "paste")
        var s = (appStyles["default"] ?? AppStyle()).merged(over: base)
        if let b = bundleId, let specific = appStyles[b] { s = specific.merged(over: s) }
        return s
    }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: Paths.configFile) else { return Config() }
        do { return try JSONDecoder().decode(Config.self, from: data) }
        catch { Log.error("config.json invalide (\(error)) : valeurs par défaut utilisées"); return Config() }
    }

    public func save() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: Paths.configFile, options: .atomic)
    }
}
