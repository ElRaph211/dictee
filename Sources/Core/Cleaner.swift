import Foundation

/// Nettoyage déterministe du texte transcrit (règles, pas de modèle) :
/// hésitations, auto-corrections dites à voix haute, ponctuation dictée, listes, majuscules.
public struct Cleaner {
    public var config: CleaningConfig
    public init(config: CleaningConfig = CleaningConfig()) { self.config = config }

    // MARK: - Listes de mots

    static let fillers: [String] = [
        // FR
        "euh", "euhh", "euuh", "euuuh", "heu", "heuu", "hum", "humm", "hmm", "hm", "bah",
        // EN
        "um", "umm", "uh", "uhh", "uhm", "erm", "mm", "mmm",
    ]

    /// Marqueurs forts : on peut supprimer les mots d'avant même sans repère commun.
    static let strongMarkers = ["non pardon", "enfin non", "euh non", "non non", "ou plutot", "non plutot", "enfin plutot",
                                "scratch that", "no wait", "wait no", "or rather", "correction", "non je veux dire", "no i mean", "sorry i mean"]
    /// Marqueurs faibles : suppression seulement si on retrouve un mot repère avant ; sinon on retire juste le marqueur.
    static let weakMarkers = ["je veux dire", "i mean"]

    static let hallucinations: Set<String> = [
        "sous-titres realises par la communaute d amara org", "sous titres realises par la communaute d amara org",
        "sous-titrage st 501", "sous-titrage societe radio-canada", "sous-titrage mfp", "merci d avoir regarde",
        "merci d avoir regarde cette video", "thank you for watching", "thanks for watching", "subtitles by the amara org community",
        "abonnez-vous", "sous-titrage", "sous titrage",
    ].map { TextUtil.key($0) }.reduce(into: Set<String>()) { $0.insert($1) }

    static let spokenBasic: [String: String] = [
        "point d'interrogation": "\u{1}?", "question mark": "\u{1}?",
        "point d'exclamation": "\u{1}!", "exclamation mark": "\u{1}!", "exclamation point": "\u{1}!",
        "nouvelle ligne": "\u{1}N", "à la ligne": "\u{1}N", "retour à la ligne": "\u{1}N", "saut de ligne": "\u{1}N",
        "new line": "\u{1}N", "newline": "\u{1}N", "line break": "\u{1}N",
        "nouveau paragraphe": "\u{1}P", "new paragraph": "\u{1}P",
    ]
    static let spokenExtended: [String: String] = [
        "virgule": "\u{1},", "comma": "\u{1},",
        "point": "\u{1}.", "period": "\u{1}.", "full stop": "\u{1}.",
        "deux points": "\u{1}:", "colon": "\u{1}:",
        "point virgule": "\u{1};", "semicolon": "\u{1};",
        "ouvre la parenthèse": "\u{1}(", "ouvrir la parenthèse": "\u{1}(", "open paren": "\u{1}(", "open parenthesis": "\u{1}(",
        "ferme la parenthèse": "\u{1})", "fermer la parenthèse": "\u{1})", "close paren": "\u{1})", "close parenthesis": "\u{1})",
    ]

    static let ordinals: [String: Int] = [
        "premièrement": 1, "deuxièmement": 2, "troisièmement": 3, "quatrièmement": 4, "cinquièmement": 5,
        "sixièmement": 6, "septièmement": 7, "huitièmement": 8, "neuvièmement": 9, "dixièmement": 10,
        "firstly": 1, "secondly": 2, "thirdly": 3, "fourthly": 4, "fifthly": 5, "sixthly": 6,
    ]
    static let bullets = ["tiret", "puce", "bullet", "bullet point", "dash"]

    // MARK: - Pipeline

    public func clean(_ raw: String, lang: String) -> String {
        var t = raw.replacingOccurrences(of: "\r", with: "")
        t = TextUtil.replace(t, "[ \\t\\u{00A0}]+", " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }

        // Bruits de Whisper sur le silence : "[Musique]", "(silence)", "*rires*"
        t = TextUtil.replace(t, "\\[[^\\]]{1,40}\\]|\\*[^*]{1,40}\\*", "")
        if TextUtil.matches(t, "^\\s*\\([^)]{1,40}\\)\\s*$") { return "" }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.hallucinations.contains(TextUtil.key(t)) { return "" }
        if TextUtil.tokens(t).isEmpty { return "" }

        if config.removeFillers { t = removeFillers(t) }
        if config.selfCorrections { t = applySelfCorrections(t) }
        if config.spokenPunctuation { t = applySpokenPunctuation(t, lang: lang) }
        if config.dropTrailingQuoi && lang == "fr" {
            t = TextUtil.replace(t, "(?i)(\\p{L})\\s*,?\\s+quoi\\s*\\.", "$1.")
        }
        if config.lists { t = formatLists(t, lang: lang) }
        t = tidyPunctuation(t, lang: lang)
        return t
    }

    // MARK: - Hésitations

    func removeFillers(_ s: String) -> String {
        let alt = Self.fillers.joined(separator: "|")
        // (virgule avant ?) filler (ponctuation après ?)
        let pattern = "(?i)(,\\s*)?(?<![\\p{L}\\p{N}'’-])(?:\(alt))(?![\\p{L}\\p{N}'’-])\\s*([,.;:!?])?\\s*"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""; var cursor = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let hadCommaBefore = m.range(at: 1).location != NSNotFound
            let after = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
            if after == "." || after == "!" || after == "?" || after == ";" || after == ":" {
                out += after + " "                     // "je pense, euh. Que" → "je pense. Que"
            } else if hadCommaBefore {
                out += " "                             // "je pense, euh, que" → "je pense que"
            } else if !after.isEmpty && !out.isEmpty && !out.hasSuffix(" ") && !out.hasSuffix("\n") {
                out += after + " "                     // "bonjour euh, je" → "bonjour, je"
            } else {
                out += ""                              // "Euh, je pense" → "je pense"
            }
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        out = TextUtil.replace(out, "\\s+([,.;:!?])", "$1")
        out = TextUtil.replace(out, "^[\\s,.;:]+", "")
        return TextUtil.replace(out, "[ ]{2,}", " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Auto-corrections ("mardi, non pardon, mercredi")

    struct WordTok { var text: String; var core: String; var endsClause: Bool; var endsSentence: Bool }

    static func wordTokens(_ s: String) -> [WordTok] {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { w in
            let t = String(w)
            let core = TextUtil.fold(t.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols)))
            let last = t.last.map(String.init) ?? ""
            return WordTok(text: t, core: core, endsClause: [",", ".", ";", ":", "!", "?"].contains(last) || t.hasSuffix("..."),
                           endsSentence: [".", "!", "?"].contains(last))
        }
    }

    func applySelfCorrections(_ s: String) -> String {
        var toks = Self.wordTokens(s)
        let markers = (Self.strongMarkers.map { ($0, true) } + Self.weakMarkers.map { ($0, false) })
            .map { (TextUtil.key($0.0).split(separator: " ").map(String.init), $0.1) }
            .sorted { $0.0.count > $1.0.count }
        var iterations = 0
        outer: while iterations < 6 {
            iterations += 1
            for m in 0..<toks.count {
                for (mk, strong) in markers {
                    guard m + mk.count <= toks.count else { continue }
                    var matches = true
                    for j in 0..<mk.count where toks[m + j].core != mk[j] { matches = false; break }
                    guard matches else { continue }
                    // le marqueur ne doit pas couper une phrase en son milieu ("ce que je veux dire")
                    if !strong, m > 0, ["que", "qu", "ce", "what", "you", "do", "i"].contains(toks[m - 1].core) { continue }
                    if !strong, m + mk.count < toks.count, ["que", "qu", "that", "it"].contains(toks[m + mk.count].core) { continue }
                    let afterStart = m + mk.count
                    // Y = mots après le marqueur jusqu'à la fin de la proposition (max 8)
                    var y: [Int] = []
                    var k = afterStart
                    while k < toks.count && y.count < 8 { y.append(k); if toks[k].endsClause { break }; k += 1 }
                    // fenêtre avant : max 10 mots, sans franchir une fin de phrase
                    var windowStart = m
                    var cnt = 0
                    while windowStart > 0 && cnt < 10 {
                        if toks[windowStart - 1].endsSentence && windowStart - 1 != m - 1 { break }
                        windowStart -= 1; cnt += 1
                    }
                    var deleteFrom: Int? = nil
                    // repère : un des 3 premiers mots de Y présent dans la fenêtre avant
                    anchor: for (j, yi) in y.prefix(3).enumerated() {
                        let core = toks[yi].core; guard !core.isEmpty else { continue }
                        var i = m - 1
                        while i >= windowStart {
                            if toks[i].core == core, i - j >= windowStart { deleteFrom = i - j; break anchor }
                            i -= 1
                        }
                    }
                    // sans repère : un marqueur fort remplace le dernier mot ("mardi, non pardon, mercredi")
                    if deleteFrom == nil, strong, !y.isEmpty, m - 1 >= windowStart {
                        deleteFrom = m - 1
                    }
                    let from = deleteFrom ?? m
                    // ponctuation de fin de proposition portée par le mot d'avant la zone effacée : on la garde si c'est une fin de phrase
                    var replaced = Array(toks[0..<from])
                    if from > 0, from < m, toks[m - 1].endsSentence, !(replaced.last?.endsSentence ?? true) {
                        // rien : la fin de phrase sera reconstruite par Y
                    }
                    replaced.append(contentsOf: toks[afterStart...])
                    toks = replaced
                    continue outer
                }
            }
            break
        }
        var out = toks.map { $0.text }.joined(separator: " ")
        out = TextUtil.replace(out, "\\s+([,.;:!?])", "$1")
        out = TextUtil.replace(out, "([,;:])\\s*[,;:]+", "$1")
        return out
    }

    // MARK: - Ponctuation dictée

    func applySpokenPunctuation(_ s: String, lang: String) -> String {
        var m = PhraseMatcher(Self.spokenBasic)
        if config.spokenPunctuationExtended { for (k, v) in Self.spokenExtended { m.add(k, v) } }
        var t = m.apply(to: s)
        guard t.contains("\u{1}") else { return s }
        // ponctuation : on efface celle que Whisper avait mise autour du marqueur
        t = TextUtil.replace(t, "\\s*[,.;:!?]*\\s*\u{1}([?!.,;:])\\s*[,.;:]*\\s*", "$1 ")
        t = TextUtil.replace(t, "\\s*[,.;:]*\\s*\u{1}\\(\\s*", " (")
        t = TextUtil.replace(t, "\\s*[,.;:]*\\s*\u{1}\\)\\s*", ") ")
        t = TextUtil.replace(t, "\\s*[,;:]*\\s*\u{1}N\\s*[,.;:]*\\s*", "\n")
        t = TextUtil.replace(t, "\\s*[,;:]*\\s*\u{1}P\\s*[,.;:]*\\s*", "\n\n")
        t = TextUtil.replace(t, "\\(\\s*\\)", "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Listes dictées

    func formatLists(_ s: String, lang: String) -> String {
        var ord = PhraseMatcher(); for (k, v) in Self.ordinals { ord.add(k, String(v)) }
        var bul = PhraseMatcher(); for b in Self.bullets { bul.add(b, "-") }
        let ordHits = ord.hits(in: s), bulHits = bul.hits(in: s)
        let hits: [PhraseMatcher.Hit]
        let numbered: Bool
        if ordHits.count >= 2 && ordHits.first?.value == "1" { hits = ordHits; numbered = true }
        else if bulHits.count >= 2 { hits = bulHits; numbered = false }
        else { return s }

        var intro = String(s[..<hits[0].range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        intro = TextUtil.replace(intro, "[,;:\\s]+$", "")
        var lines: [String] = []
        if !intro.isEmpty {
            if !TextUtil.matches(intro, "[.!?:]$") { intro += (lang == "fr" ? " :" : ":") }
            lines.append(intro)
        }
        for (i, h) in hits.enumerated() {
            let end = i + 1 < hits.count ? hits[i + 1].range.lowerBound : s.endIndex
            var item = String(s[h.range.upperBound..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            item = TextUtil.replace(item, "^[,;:.\\s]+", "")
            item = TextUtil.replace(item, "[,;:\\s]+$", "")
            item = TextUtil.capitalizeFirst(item)
            guard !item.isEmpty else { continue }
            lines.append(numbered ? "\(h.value). \(item)" : "- \(item)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Finitions

    func tidyPunctuation(_ s: String, lang: String) -> String {
        var t = s
        t = TextUtil.replace(t, "[ \\t]+\\n", "\n")
        t = TextUtil.replace(t, "\\n[ \\t]+", "\n")
        t = TextUtil.replace(t, "\\n{3,}", "\n\n")
        t = TextUtil.replace(t, "\\s+([,.])", "$1")
        t = TextUtil.replace(t, "([,;:!?])(\\s*[,;:!?])+", "$1")
        t = TextUtil.replace(t, ",\\s*\\.", ".")
        t = TextUtil.replace(t, "(?<!\\.)\\.\\s*\\.(?!\\.)", ".")
        if lang == "fr" {
            t = TextUtil.replace(t, "\\s*([;:!?])", " $1")      // typographie française : espace avant ; : ! ?
            t = TextUtil.replace(t, "\\(\\s+", "(")
        } else {
            t = TextUtil.replace(t, "\\s+([;:!?])", "$1")
        }
        t = TextUtil.replace(t, "([,.;:!?])(?=[\\p{L}\\p{N}])", "$1 ")   // espace après ponctuation
        t = TextUtil.replace(t, "(\\p{N})\\. (\\p{N}{3})", "$1.$2")       // on ne casse pas "1.000"
        t = TextUtil.replace(t, "(\\p{L}{1,4})\\. (com|fr|io|ai|org|net)\\b", "$1.$2")   // cal.com
        t = TextUtil.replace(t, "[ ]{2,}", " ")
        // majuscule après fin de phrase / retour à la ligne
        t = capitalizeSentences(t)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func capitalizeSentences(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "(^|[.!?]\\s+|\\n\\s*)(\\p{Ll})") else { return s }
        let ns = NSMutableString(string: s)
        let ms = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        for m in ms.reversed() {
            let r = m.range(at: 2)
            ns.replaceCharacters(in: r, with: ns.substring(with: r).uppercased())
        }
        return ns as String
    }
    func capitalizeSentences(_ s: String) -> String { Self.capitalizeSentences(s) }
}

/// Style final selon l'application (majuscule initiale, point final, espace de fin).
public enum Styler {
    public static func apply(_ text: String, style: AppStyle, protectedKeys: Set<String> = []) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if style.capitalizeFirst ?? true {
            t = TextUtil.capitalizeFirst(t)
        } else if let first = TextUtil.tokens(t).first, !protectedKeys.contains(first.folded), first.text.dropFirst().allSatisfy({ $0.isLowercase || !$0.isLetter }) {
            t = TextUtil.lowercaseFirst(t)
        }
        if style.trailingPunctuation ?? true {
            if let last = t.last, last.isLetter || last.isNumber { t += "." }
        } else {
            t = TextUtil.replace(t, "\\.$", "")
        }
        if style.trailingSpace ?? false { t += " " }
        return t
    }
}
