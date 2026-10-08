import Foundation

/// Journal simple : ~/Library/Logs/Dictee/dictee.log (+ stderr). Rotation à 2 Mo.
public enum Log {
    private static let queue = DispatchQueue(label: "dictee.log")
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()
    public static var mirrorToStderr = true
    private static var fileURL: URL { Paths.logsDir.appendingPathComponent("dictee.log") }

    public static func info(_ m: String) { write("INFO", m) }
    public static func warn(_ m: String) { write("WARN", m) }
    public static func error(_ m: String) { write("ERROR", m) }

    private static func write(_ level: String, _ m: String) {
        let line = "\(fmt.string(from: Date())) [\(level)] \(m)\n"
        if mirrorToStderr { FileHandle.standardError.write(line.data(using: .utf8)!) }
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: Paths.logsDir, withIntermediateDirectories: true)
            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path), let size = attrs[.size] as? Int, size > 2_000_000 {
                let old = Paths.logsDir.appendingPathComponent("dictee.log.1")
                try? fm.removeItem(at: old); try? fm.moveItem(at: fileURL, to: old)
            }
            if let h = try? FileHandle(forWritingTo: fileURL) {
                h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
            } else {
                try? line.data(using: .utf8)!.write(to: fileURL)
            }
        }
    }
}
