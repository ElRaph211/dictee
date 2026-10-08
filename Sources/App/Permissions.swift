import Cocoa
import AVFoundation
import ApplicationServices

/// Vérification des trois autorisations nécessaires, avec explication si l'une manque.
enum Permissions {
    struct Status {
        var microphone: Bool
        var accessibility: Bool
        var inputMonitoring: Bool
        var allGranted: Bool { microphone && accessibility && inputMonitoring }
        var missingSummary: String {
            var m: [String] = []
            if !microphone { m.append("Microphone") }
            if !accessibility { m.append("Accessibilité") }
            if !inputMonitoring { m.append("Surveillance de l'entrée") }
            return m.joined(separator: ", ")
        }
    }

    static func check() -> Status {
        Status(microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               accessibility: AXIsProcessTrusted(),
               inputMonitoring: CGPreflightListenEventAccess())
    }

    /// Demande ce qui peut l'être (fait apparaître l'app dans Réglages Système).
    static func request() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { ok in Log.info("Micro accordé : \(ok)") }
        }
        if !AXIsProcessTrusted() {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }

    static func explainIfMissing() -> Bool {
        let s = check()
        guard !s.allGranted else { return true }
        Log.warn("Autorisations manquantes : \(s.missingSummary)")
        let alert = NSAlert()
        alert.messageText = "Dictee a besoin d'autorisations"
        alert.informativeText = """
        Il manque : \(s.missingSummary).

        Ouvre Réglages Système > Confidentialité et sécurité, puis active « Dictee » dans :
        • Microphone
        • Accessibilité
        • Surveillance de l'entrée

        Pense aussi à :
        • Réglages > Clavier > « Appuyer sur la touche 🌐 pour » → « Ne rien faire »
        • Quitter Wispr Flow (conflit sur la touche fn)

        Puis relance Dictee (menu barre > Relancer).
        """
        alert.addButton(withTitle: "Ouvrir les Réglages")
        alert.addButton(withTitle: "Plus tard")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let urls = [
                !s.microphone ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone" : nil,
                !s.accessibility ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" : nil,
                !s.inputMonitoring ? "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" : nil,
            ].compactMap { $0 }
            if let u = urls.first.flatMap(URL.init(string:)) { NSWorkspace.shared.open(u) }
        }
        return false
    }
}
