import Cocoa

/// Fenêtre « Copier le texte » (comme Wispr Flow) quand la dictée n'a pas pu être collée : aucun
/// champ de texte actif. Ne vole pas le focus (panneau non activant), se ferme seule après 15 s.
final class CopyPopup {
    private var panel: NSPanel?
    private var closeWork: DispatchWorkItem?

    func show(text: String, theme: String) {
        DispatchQueue.main.async { self.showOnMain(text: text, dark: theme != "howseen" || Self.systemDark) }
    }

    private static var systemDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func showOnMain(text: String, dark: Bool) {
        close()
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 420, height: 132)
        let vf = screen.visibleFrame
        let frame = NSRect(x: vf.midX - size.width / 2, y: vf.minY + 76, width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.hasShadow = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let ink = NSColor(srgbRed: 0x0f / 255, green: 0x17 / 255, blue: 0x2a / 255, alpha: 1)
        let blue = NSColor(srgbRed: 0x00 / 255, green: 0xa5 / 255, blue: 0xeb / 255, alpha: 1)
        let bg = dark ? ink : .white
        let fg = dark ? NSColor.white : ink
        let muted = dark ? NSColor(white: 1, alpha: 0.6) : NSColor(srgbRed: 0.39, green: 0.45, blue: 0.55, alpha: 1)

        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = bg.cgColor
        box.layer?.cornerRadius = 14
        box.layer?.borderWidth = 1
        box.layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.08)).cgColor

        let title = NSTextField(labelWithString: "Aucun champ de texte actif : ta dictée n'a pas été collée.")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = muted
        title.frame = NSRect(x: 16, y: size.height - 30, width: size.width - 48, height: 16)

        let body = NSTextField(wrappingLabelWithString: text)
        body.font = .systemFont(ofSize: 13)
        body.textColor = fg
        body.maximumNumberOfLines = 3
        body.lineBreakMode = .byTruncatingTail
        body.frame = NSRect(x: 16, y: 46, width: size.width - 32, height: 50)

        let copy = NSButton(title: "Copier le texte", target: nil, action: nil)
        copy.bezelStyle = .rounded
        copy.contentTintColor = blue
        copy.keyEquivalent = "\r"
        copy.frame = NSRect(x: size.width - 146, y: 10, width: 130, height: 28)
        copy.target = self
        copy.action = #selector(copyTapped(_:))
        copy.identifier = NSUserInterfaceItemIdentifier(text)

        let x = NSButton(title: "✕", target: self, action: #selector(closeTapped))
        x.isBordered = false
        x.font = .systemFont(ofSize: 12)
        x.contentTintColor = muted
        x.frame = NSRect(x: size.width - 30, y: size.height - 32, width: 20, height: 20)

        for v in [title, body, copy, x] { box.addSubview(v) }
        p.contentView = box
        p.orderFrontRegardless()
        panel = p

        let work = DispatchWorkItem { [weak self] in self?.close() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    @objc private func copyTapped(_ sender: NSButton) {
        let text = sender.identifier?.rawValue ?? ""
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        sender.title = "Copié ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.close() }
    }

    @objc private func closeTapped() { close() }

    func close() {
        closeWork?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }
}
