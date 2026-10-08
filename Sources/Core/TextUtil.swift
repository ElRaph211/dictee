import Foundation

/// Petits utilitaires texte (regex, normalisation), partagés par le nettoyage et l'apprentissage.
public enum TextUtil {
    /// Minuscules sans accents : "Perplexité" → "perplexite". Sert de clé de comparaison.
    public static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// Mots = suites de lettres/chiffres (l'apostrophe et le tiret séparent).
    public struct Token { public let text: String; public let range: Range<String.Index>; public let folded: String }

    private static let tokenRegex = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+")

    public static func tokens(_ s: String) -> [Token] {
        let ns = s as NSString
        return tokenRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let r = Range(m.range, in: s) else { return nil }
            let t = String(s[r]); return Token(text: t, range: r, folded: fold(t))
        }
    }

    /// Clé normalisée d'une phrase : mots pliés joints par un espace.
    public static func key(_ phrase: String) -> String { tokens(phrase).map { $0.folded }.joined(separator: " ") }

    public static func replace(_ s: String, _ pattern: String, _ template: String, options: NSRegularExpression.Options = []) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    public static func matches(_ s: String, _ pattern: String, options: NSRegularExpression.Options = []) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        return re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// Majuscule sur la première lettre (laisse le reste intact).
    public static func capitalizeFirst(_ s: String) -> String {
        guard let i = s.firstIndex(where: { $0.isLetter }) else { return s }
        return String(s[..<i]) + String(s[i]).uppercased() + String(s[s.index(after: i)...])
    }
    public static func lowercaseFirst(_ s: String) -> String {
        guard let i = s.firstIndex(where: { $0.isLetter }) else { return s }
        return String(s[..<i]) + String(s[i]).lowercased() + String(s[s.index(after: i)...])
    }

    /// Distance de Levenshtein (sur les clés pliées), pour juger la proximité d'une correction.
    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }; if b.isEmpty { return a.count }
        var prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
    public static func similarity(_ a: String, _ b: String) -> Double {
        let n = max(a.count, b.count); if n == 0 { return 1 }
        return 1 - Double(levenshtein(a, b)) / Double(n)
    }
}

/// Remplacement de phrases par clé normalisée (insensible à la casse et aux accents),
/// le plus long d'abord, sur des mots entiers. Utilisé pour le dictionnaire, les snippets,
/// la ponctuation dictée et les listes.
public struct PhraseMatcher {
    public struct Hit { public let range: Range<String.Index>; public let key: String; public let value: String }
    private var map: [String: String] = [:]
    private var maxWords = 1

    public init(_ pairs: [String: String] = [:]) { for (k, v) in pairs { add(k, v) } }

    public mutating func add(_ phrase: String, _ value: String) {
        let k = TextUtil.key(phrase); guard !k.isEmpty else { return }
        map[k] = value; maxWords = max(maxWords, k.split(separator: " ").count)
    }
    public var isEmpty: Bool { map.isEmpty }
    public func value(forKey k: String) -> String? { map[k] }

    /// Les mots consécutifs doivent n'être séparés que par des espaces, tirets ou apostrophes.
    private static func contiguous(_ s: String, _ a: TextUtil.Token, _ b: TextUtil.Token) -> Bool {
        let gap = s[a.range.upperBound..<b.range.lowerBound]
        return !gap.isEmpty && gap.allSatisfy { $0 == " " || $0 == "-" || $0 == "'" || $0 == "’" || $0 == "\u{00A0}" }
    }

    public func hits(in s: String) -> [Hit] {
        let toks = TextUtil.tokens(s); var out: [Hit] = []; var i = 0
        while i < toks.count {
            var found = false
            for n in stride(from: min(maxWords, toks.count - i), through: 1, by: -1) {
                var ok = true
                if n > 1 { for j in i..<(i + n - 1) where !Self.contiguous(s, toks[j], toks[j + 1]) { ok = false; break } }
                guard ok else { continue }
                let k = toks[i..<(i + n)].map { $0.folded }.joined(separator: " ")
                if let v = map[k] {
                    out.append(Hit(range: toks[i].range.lowerBound..<toks[i + n - 1].range.upperBound, key: k, value: v))
                    i += n; found = true; break
                }
            }
            if !found { i += 1 }
        }
        return out
    }

    /// Remplace toutes les occurrences. `transform` permet d'adapter la valeur (ex : garder la casse d'origine).
    public func apply(to s: String, transform: ((Hit) -> String)? = nil) -> String {
        let hs = hits(in: s); guard !hs.isEmpty else { return s }
        var out = ""; var cursor = s.startIndex
        for h in hs {
            out += s[cursor..<h.range.lowerBound]; out += transform?(h) ?? h.value; cursor = h.range.upperBound
        }
        out += s[cursor...]; return out
    }
}
