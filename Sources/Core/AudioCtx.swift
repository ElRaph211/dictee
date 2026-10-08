import Foundation

/// Formule du contexte audio dynamique, isolée pour être testable sans whisper.cpp.
public enum WhisperEngineCtx {
    public static func audioCtx(_ seconds: Double) -> Int32 {
        let units = Int(((seconds + 6.0) / 30.0 * 1500.0).rounded(.up))
        let rounded = ((units + 255) / 256) * 256
        return Int32(min(1500, max(768, rounded)))
    }
}
