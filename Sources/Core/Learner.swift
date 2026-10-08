import Foundation

/// Apprentissage des corrections, façon Wispr Flow :
/// on compare le texte collé avec le contenu du champ relu quelques secondes plus tard (Accessibilité).
/// Chaque mot corrigé devient un candidat ; au bout de `threshold` observations identiques il entre au dictionnaire.
public struct Correction: Equatable, Hashable {
    public let original: String
    public let corrected: String
    /// true = même mot, seule la casse change ("posthog" → "PostHog") : on l'ajoute aux "words".
    public var isCasingOnly: Bool { TextUtil.key(original) == TextUtil.key(corrected) }
}

public struct LearnedStore: Codable {
    public struct Candidate: Codable, Equatable {
        public var original: String
        public var corrected: String
        public var count: Int
        public var last: String
    }
    public var candidates: [String: Candidate] = [:]
    public init() {}

    public static func load(from url: URL = Paths.learnedFile) -> LearnedStore {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(LearnedStore.self, from: data) else { return LearnedStore() }
        return s
    }
    public func save(to url: URL = Paths.learnedFile) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

public enum Learner {
    static let stopWords: Set<String> = ["le", "la", "les", "un", "une", "des", "de", "du", "et", "ou", "a", "à", "en", "y", "the", "an", "of", "and", "or", "to", "in", "on", "is", "it", "je", "tu", "il", "on", "ne", "pas", "que", "qui", "ce", "se", "ça", "sa", "son", "ses", "me", "te", "mon", "ma", "mes"].map { TextUtil.fold($0) }.reduce(into: Set<String>()) { $0.insert($1) }

    // MARK: Diff mot à mot (LCS)

    /// Opérations du diff, en indices dans les deux listes de mots.
    enum Op { case equal(Int, Int), replace(Range<Int>, Range<Int>), delete(Range<Int>), insert(Range<Int>) }

    static func diff(_ a: [TextUtil.Token], _ b: [TextUtil.Token]) -> [Op] {
        let n = a.count, m = b.count
        guard n > 0, m > 0 else {
            if n > 0 { return [.delete(0..<n)] }
            if m > 0 { return [.insert(0..<m)] }
            return []
        }
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = a[i].folded == b[j].folded ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var ops: [Op] = []; var i = 0, j = 0
        var pa = 0, pb = 0   // début des zones en attente
        var na = 0, nb = 0   // longueurs en attente
        func flush() {
            if na > 0 && nb > 0 { ops.append(.replace(pa..<(pa + na), pb..<(pb + nb))) }
            else if na > 0 { ops.append(.delete(pa..<(pa + na))) }
            else if nb > 0 { ops.append(.insert(pb..<(pb + nb))) }
            na = 0; nb = 0
        }
        while i < n && j < m {
            if a[i].folded == b[j].folded { flush(); ops.append(.equal(i, j)); i += 1; j += 1; pa = i; pb = j }
            else if dp[i + 1][j] >= dp[i][j + 1] { if na == 0 { pa = i }; na += 1; i += 1 }
            else { if nb == 0 { pb = j }; nb += 1; j += 1 }
        }
        if i < n { if na == 0 { pa = i }; na += n - i }
        if j < m { if nb == 0 { pb = j }; nb += m - j }
        flush()
        return ops
    }

    /// Réduit un long contenu (terminal, document) à la zone qui ressemble le plus au texte collé.
    static func window(_ observed: [TextUtil.Token], around pasted: [TextUtil.Token]) -> [TextUtil.Token] {
        let size = pasted.count + 20
        guard observed.count > size + 20 else { return observed }
        let bag = Set(pasted.map { $0.folded })
        var best = 0, bestScore = -1
        var start = 0
        while start < observed.count {
            let end = min(observed.count, start + size)
            let score = observed[start..<end].reduce(0) { $0 + (bag.contains($1.folded) ? 1 : 0) }
            if score > bestScore { bestScore = score; best = start }
            start += max(1, pasted.count / 2)
        }
        return Array(observed[best..<min(observed.count, best + size)])
    }

    /// Corrections repérées entre le texte collé et le texte observé ensuite.
    public static func corrections(pasted: String, observed: String, dictionary: PersonalDictionary) -> [Correction] {
        let a = TextUtil.tokens(pasted)
        guard !a.isEmpty, !observed.isEmpty else { return [] }
        if observed.contains(pasted) { return [] }
        let b = window(TextUtil.tokens(observed), around: a)
        guard !b.isEmpty else { return [] }
        let ops = diff(a, b)
        // Si moins de la moitié des mots collés sont retrouvés, le champ a changé de contenu : on n'apprend rien.
        let equalCount = ops.reduce(0) { if case .equal = $1 { return $0 + 1 } else { return $0 } }
        guard Double(equalCount) >= Double(a.count) * 0.5 else { return [] }

        /// Un mot en début de phrase prend naturellement une majuscule : on ne l'apprend pas.
        func sentenceInitial(_ i: Int) -> Bool {
            if i == 0 { return true }
            let between = pasted[a[i - 1].range.upperBound..<a[i].range.lowerBound]
            return between.contains(where: { ".!?\n".contains($0) })
        }
        func isEqual(_ op: Op) -> Bool { if case .equal = op { return true } else { return false } }

        var out: [Correction] = []
        for (idx, op) in ops.enumerated() {
            switch op {
            case .equal(let i, let j):
                // même mot, casse différente ("brevo" → "Brevo")
                let o = a[i].text, c = b[j].text
                guard o != c, !sentenceInitial(i), c.contains(where: { $0.isUppercase }) else { continue }
                guard TextUtil.key(o).count >= 2, !stopWords.contains(a[i].folded) else { continue }
                if dictionary.hasWord(c) { continue }
                out.append(Correction(original: o, corrected: c))
            case .replace(let ra, let rb):
                guard ra.count <= 3, rb.count <= 3 else { continue }
                let anchoredBefore = idx > 0 && isEqual(ops[idx - 1])
                let anchoredAfter = idx + 1 < ops.count && isEqual(ops[idx + 1])
                guard anchoredBefore || anchoredAfter || (a.count == 1 && ra.count == 1 && rb.count == 1) else { continue }
                let o = ra.map { a[$0].text }.joined(separator: " "), c = rb.map { b[$0].text }.joined(separator: " ")
                let ko = TextUtil.key(o), kc = TextUtil.key(c)
                guard ko.count >= 2, !ko.allSatisfy({ $0.isNumber || $0 == " " }), !kc.allSatisfy({ $0.isNumber || $0 == " " }) else { continue }
                if ra.count == 1 && stopWords.contains(ko) { continue }
                // ressemble à une correction de terme (pas une reformulation)
                let hasInnerCaps = c.contains { $0.isUppercase } && !(sentenceInitial(ra.lowerBound) && TextUtil.capitalizeFirst(c) == c && !c.dropFirst().contains(where: { $0.isUppercase }) && TextUtil.similarity(ko, kc) < 0.4)
                let sim = TextUtil.similarity(ko, kc)
                let sameInitial = ko.first == kc.first
                guard hasInnerCaps || sim >= 0.4 || (sameInitial && ra.count == rb.count) else { continue }
                if dictionary.contains(rule: o, c) { continue }
                out.append(Correction(original: o, corrected: c))
            default: continue
            }
        }
        return out
    }

    /// Enregistre les corrections dans le store et promeut celles qui atteignent le seuil.
    /// Retourne les règles ajoutées au dictionnaire (pour notifier l'utilisateur).
    @discardableResult
    public static func learn(_ corrections: [Correction], store: inout LearnedStore, dictionary: inout PersonalDictionary, threshold: Int) -> [Correction] {
        var promoted: [Correction] = []
        let now = ISO8601DateFormatter().string(from: Date())
        for c in corrections {
            let id = TextUtil.key(c.original) + "\u{0}" + c.corrected
            var cand = store.candidates[id] ?? LearnedStore.Candidate(original: c.original, corrected: c.corrected, count: 0, last: now)
            cand.count += 1; cand.last = now
            if cand.count >= max(1, threshold) {
                if c.isCasingOnly {
                    if !dictionary.hasWord(c.corrected) { dictionary.words.append(c.corrected) }
                } else {
                    dictionary.learned[c.original.lowercased()] = c.corrected
                }
                promoted.append(c)
                store.candidates.removeValue(forKey: id)
            } else {
                store.candidates[id] = cand
            }
        }
        return promoted
    }
}
