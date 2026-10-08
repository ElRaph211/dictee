import Foundation
import AVFoundation

/// Lecture d'un fichier audio (wav, aiff, m4a...) en PCM float32 mono 16 kHz, pour les tests et la CLI.
public enum AudioFile {
    public static func loadMono16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let src = file.processingFormat
        guard let dst = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: src, to: dst) else {
            throw NSError(domain: "Dictee", code: 2, userInfo: [NSLocalizedDescriptionKey: "Format audio non convertible"])
        }
        let frames = AVAudioFrameCount(file.length)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: frames) else { throw NSError(domain: "Dictee", code: 3) }
        try file.read(into: inBuf)
        let outCap = AVAudioFrameCount(Double(frames) * 16000.0 / src.sampleRate) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: outCap) else { throw NSError(domain: "Dictee", code: 3) }
        var consumed = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true; status.pointee = .haveData; return inBuf
        }
        if let err = err { throw err }
        guard let ch = outBuf.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(outBuf.frameLength)))
    }
}
