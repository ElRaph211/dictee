import Foundation

/// Dictionnaire personnel (~/.config/dictee/dictionary.json) :
///  - "words"        : mots et noms propres, injectés dans le prompt Whisper et dont la casse est imposée
///  - "replacements" : règles écrites à la main ("jipitou" → "GPT")
///  - "learned"      : règles apprises automatiquement à partir des corrections de l'utilisateur
public struct PersonalDictionary: Codable, Equatable {
    public var words: [String] = []
    public var replacements: [String: String] = [:]
    public var learned: [String: String] = [:]

    public init(words: [String] = [], replacements: [String: String] = [:], learned: [String: String] = [:]) {
        self.words = words; self.replacements = replacements; self.learned = learned
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        words = try c.decodeIfPresent([String].self, forKey: .words) ?? []
        replacements = try c.decodeIfPresent([String: String].self, forKey: .replacements) ?? [:]
        learned = try c.decodeIfPresent([String: String].self, forKey: .learned) ?? [:]
    }

    public static func load(from url: URL = Paths.dictionaryFile) -> PersonalDictionary {
        guard let data = try? Data(contentsOf: url) else { return PersonalDictionary() }
        do { return try JSONDecoder().decode(PersonalDictionary.self, from: data) }
        catch { Log.error("dictionary.json invalide (\(error)) : dictionnaire vide utilisé"); return PersonalDictionary() }
    }

    public func save(to url: URL = Paths.dictionaryFile) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(self).write(to: url, options: .atomic)
    }

    /// Clés pliées de tous les mots connus (pour protéger leur casse, ex. en début de phrase).
    public var knownKeys: Set<String> {
        var s = Set(words.map { TextUtil.key($0) })
        for v in replacements.values { s.insert(TextUtil.key(v)) }
        for v in learned.values { s.insert(TextUtil.key(v)) }
        return s
    }

    /// Prompt initial pour Whisper : liste des noms propres, bornée (le modèle n'en garde que ~200 tokens).
    public func initialPrompt(maxChars: Int = 400) -> String {
        var seen = Set<String>(), out: [String] = [], len = 0
        for w in words + Array(replacements.values).sorted() + Array(learned.values).sorted() {
            let k = TextUtil.key(w); guard !k.isEmpty, !seen.contains(k) else { continue }
            if len + w.count + 2 > maxChars { break }
            seen.insert(k); out.append(w); len += w.count + 2
        }
        return out.joined(separator: ", ") + (out.isEmpty ? "" : ".")
    }

    /// Applique règles (manuelles puis apprises) puis impose la casse des mots connus.
    public func apply(to text: String) -> String {
        var rules = PhraseMatcher()
        for (k, v) in learned { rules.add(k, v) }
        for (k, v) in replacements { rules.add(k, v) }   // les règles manuelles priment
        var out = rules.isEmpty ? text : rules.apply(to: text)
        var casing = PhraseMatcher()
        for w in words { casing.add(w, w) }
        if !casing.isEmpty { out = casing.apply(to: out) }
        return out
    }

    public func contains(rule orig: String, _ corrected: String) -> Bool {
        let k = TextUtil.key(orig)
        if let v = replacements[k] ?? replacements.first(where: { TextUtil.key($0.key) == k })?.value, v == corrected { return true }
        if let v = learned[k] ?? learned.first(where: { TextUtil.key($0.key) == k })?.value, v == corrected { return true }
        return false
    }
    public func hasWord(_ w: String) -> Bool { words.contains { $0 == w } }
}

/// Snippets vocaux (~/.config/dictee/snippets.json) : {"mon lien calendrier": "https://..."}.
/// La phrase est reconnue n'importe où dans la dictée, sans tenir compte de la casse ni des accents.
public struct Snippets {
    public var map: [String: String] = [:]
    public init(_ map: [String: String] = [:]) { self.map = map }

    public static func load(from url: URL = Paths.snippetsFile) -> Snippets {
        guard let data = try? Data(contentsOf: url) else { return Snippets() }
        if let m = try? JSONDecoder().decode([String: String].self, from: data) { return Snippets(m) }
        Log.error("snippets.json invalide : ignoré"); return Snippets()
    }

    public func apply(to text: String) -> String {
        guard !map.isEmpty else { return text }
        let m = PhraseMatcher(map)
        var out = m.apply(to: text)
        // Si la dictée n'était que le snippet, on ne garde ni point final ni ponctuation parasite autour.
        if let only = map.first(where: { TextUtil.key($0.key) == TextUtil.key(text) }) { out = only.value }
        return out
    }
}
