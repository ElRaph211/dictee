import Cocoa
import ApplicationServices

/// Collage au curseur dans l'app active, sans écraser le presse-papiers (sauvegarde puis restauration),
/// et relecture du champ de texte via l'Accessibilité pour l'apprentissage.
enum Paster {
    static func frontmostApp() -> (bundleId: String?, name: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }

    /// Colle `text` au curseur. `method` : "paste" (Cmd+V, rapide) ou "type" (frappe caractère par caractère).
    static func paste(_ text: String, method: String = "paste") {
        guard !text.isEmpty else { return }
        if method == "type" { typeText(text); return }

        let pb = NSPasteboard.general
        // sauvegarde du presse-papiers (toutes les représentations texte/image classiques)
        var saved: [(NSPasteboard.PasteboardType, Data)] = []
        for item in pb.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) { saved.append((type, data)) }
            }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)

        sendCmdV()

        // restauration après que l'app cible a lu le presse-papiers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            pb.clearContents()
            guard !saved.isEmpty else { return }
            let item = NSPasteboardItem()
            for (type, data) in saved { item.setData(data, forType: type) }
            pb.writeObjects([item])
        }
    }

    private static func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)   // kVK_ANSI_V
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func typeText(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for chunk in text.chunks(of: 16) {
            let utf16 = Array(chunk.utf16)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.post(tap: .cghidEventTap)
            usleep(8000)
        }
    }

    /// Valeur du champ de texte qui a le focus (via AXUIElement), pour l'apprentissage des corrections.
    static func focusedFieldText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused, CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(el as AnyObject, to: AXUIElement.self)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let s = value as? String, !s.isEmpty { return s }
        // certains éditeurs n'exposent que le texte sélectionnable
        if AXUIElementCopyAttributeValue(element, "AXSelectedText" as CFString, &value) == .success,
           let s = value as? String, !s.isEmpty { return s }
        return nil
    }
}

extension String {
    func chunks(of size: Int) -> [Substring] {
        var out: [Substring] = []; var i = startIndex
        while i < endIndex {
            let j = index(i, offsetBy: size, limitedBy: endIndex) ?? endIndex
            out.append(self[i..<j]); i = j
        }
        return out
    }
}
