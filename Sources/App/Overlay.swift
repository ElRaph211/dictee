import Cocoa

/// Pastille flottante discrète en bas de l'écran : niveau audio pendant l'écoute, spinner pendant la transcription.
final class Overlay {
    private var window: NSWindow?
    private var barsView: BarsView?

    enum Mode { case listening(handsFree: Bool), transcribing }

    func show(_ mode: Mode) {
        DispatchQueue.main.async { self.showOnMain(mode) }
    }
    func hide() {
        DispatchQueue.main.async { self.window?.orderOut(nil); self.window = nil; self.barsView = nil }
    }
    func level(_ v: Float) {
        DispatchQueue.main.async { self.barsView?.push(level: v) }
    }

    private func showOnMain(_ mode: Mode) {
        if window == nil {
            let size = NSSize(width: 148, height: 36)
            guard let screen = NSScreen.main else { return }
            let frame = NSRect(x: screen.visibleFrame.midX - size.width / 2,
                               y: screen.visibleFrame.minY + 28, width: size.width, height: size.height)
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .statusBar
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            w.hasShadow = false
            let v = BarsView(frame: NSRect(origin: .zero, size: size))
            w.contentView = v
            barsView = v
            window = w
        }
        switch mode {
        case .listening(let handsFree): barsView?.set(mode: handsFree ? .handsFree : .listening)
        case .transcribing: barsView?.set(mode: .transcribing)
        }
        window?.orderFrontRegardless()
    }

    /// Vue : capsule sombre + barres de niveau (ou points animés en transcription).
    final class BarsView: NSView {
        enum Mode { case listening, handsFree, transcribing }
        private var mode: Mode = .listening
        private var levels = [Float](repeating: 0.05, count: 14)
        private var phase = 0.0
        private var timer: Timer?

        func set(mode: Mode) {
            self.mode = mode
            timer?.invalidate()
            if mode == .transcribing {
                timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                    self?.phase += 0.25; self?.needsDisplay = true
                }
            }
            needsDisplay = true
        }
        func push(level: Float) {
            levels.removeFirst(); levels.append(max(0.05, min(1, level)))
            if mode != .transcribing { needsDisplay = true }
        }
        deinit { timer?.invalidate() }

        override func draw(_ dirtyRect: NSRect) {
            let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: bounds.height / 2 - 1, yRadius: bounds.height / 2 - 1)
            NSColor.black.withAlphaComponent(0.78).setFill()
            capsule.fill()
            let tint: NSColor = mode == .handsFree ? .systemOrange : (mode == .transcribing ? .systemBlue : .systemGreen)

            // point d'état à gauche
            let dot = NSRect(x: 12, y: bounds.midY - 3.5, width: 7, height: 7)
            tint.setFill(); NSBezierPath(ovalIn: dot).fill()

            let startX: CGFloat = 28
            let w: CGFloat = 5, gap: CGFloat = 3.2
            for (i, l) in levels.enumerated() {
                let x = startX + CGFloat(i) * (w + gap)
                var h: CGFloat
                if mode == .transcribing {
                    h = 4 + 8 * CGFloat(abs(sin(phase + Double(i) * 0.55)))
                    NSColor.white.withAlphaComponent(0.85).setFill()
                } else {
                    h = max(3, CGFloat(l) * (bounds.height - 14))
                    NSColor.white.withAlphaComponent(0.92).setFill()
                }
                let bar = NSRect(x: x, y: bounds.midY - h / 2, width: w, height: h)
                NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
            }
        }
    }
}

/// Petits sons de début/fin (sons système, légers), optionnels.
enum Sounds {
    static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
    static func start() { play("Tink") }
    static func stop() { play("Pop") }
    static func error() { play("Basso") }
}
