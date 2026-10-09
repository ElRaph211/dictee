import Cocoa

/// Pastille flottante discrète : niveau audio pendant l'écoute, barres animées pendant la transcription.
/// Thèmes (config.json > "overlay") :
///  - "howseen" : palette du site Howseen (bleu #00a5eb, accent #e7f7ff, profond #005b8d, encre #0f172a),
///                capsule blanche en mode clair / encre en mode sombre, aucun dégradé, aucun ambre.
///  - "dark"    : capsule noire translucide, barres blanches (défaut du paquet partagé).
final class Overlay {
    private var window: NSWindow?
    private var barsView: BarsView?
    private var currentConfig = OverlayConfig()

    enum Mode { case listening(handsFree: Bool), transcribing }

    func show(_ mode: Mode, config: OverlayConfig) {
        DispatchQueue.main.async { self.showOnMain(mode, config: config) }
    }
    func hide() {
        DispatchQueue.main.async { self.window?.orderOut(nil); self.window = nil; self.barsView = nil }
    }
    func level(_ v: Float) {
        DispatchQueue.main.async { self.barsView?.push(level: v) }
    }

    private func showOnMain(_ mode: Mode, config: OverlayConfig) {
        if window == nil || config != currentConfig {
            window?.orderOut(nil)
            currentConfig = config
            let scale = CGFloat(config.scale)
            let size = NSSize(width: 192 * scale, height: 40 * scale)
            guard let screen = NSScreen.main else { return }
            let vf = screen.visibleFrame
            let y = config.position == "top" ? vf.maxY - size.height - 10 : vf.minY + 24
            let frame = NSRect(x: vf.midX - size.width / 2, y: y, width: size.width, height: size.height)
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .statusBar
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            w.hasShadow = config.theme == "howseen"
            let v = BarsView(frame: NSRect(origin: .zero, size: size))
            v.theme = config.theme == "howseen" ? .howseen : .dark
            v.scale = scale
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

    /// Palette Howseen (site/preview.html) : une seule couleur de marque, deux fonds selon l'apparence système.
    enum Howseen {
        static let blue = NSColor(srgbRed: 0x00 / 255, green: 0xa5 / 255, blue: 0xeb / 255, alpha: 1)      // #00a5eb
        static let deep = NSColor(srgbRed: 0x00 / 255, green: 0x5b / 255, blue: 0x8d / 255, alpha: 1)      // #005b8d
        static let accent = NSColor(srgbRed: 0xe7 / 255, green: 0xf7 / 255, blue: 0xff / 255, alpha: 1)    // #e7f7ff
        static let border = NSColor(srgbRed: 0xe5 / 255, green: 0xe5 / 255, blue: 0xe5 / 255, alpha: 1)    // #e5e5e5
        static let ink = NSColor(srgbRed: 0x0f / 255, green: 0x17 / 255, blue: 0x2a / 255, alpha: 1)       // #0f172a
        static let inkBorder = NSColor(srgbRed: 0x1e / 255, green: 0x29 / 255, blue: 0x3b / 255, alpha: 1) // #1e293b
        static let track = NSColor(srgbRed: 0xed / 255, green: 0xf1 / 255, blue: 0xf5 / 255, alpha: 1)     // #edf1f5
        static let sky = NSColor(srgbRed: 0x38 / 255, green: 0xbd / 255, blue: 0xf8 / 255, alpha: 1)       // #38bdf8
    }

    final class BarsView: NSView {
        enum Mode { case listening, handsFree, transcribing }
        enum Theme { case howseen, dark }
        var theme: Theme = .dark
        var scale: CGFloat = 1
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

        private var isDarkAppearance: Bool {
            effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        override func draw(_ dirtyRect: NSRect) {
            let r = bounds.insetBy(dx: 1, dy: 1)
            let capsule = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)

            let fill: NSColor, border: NSColor?, bar: NSColor, dot: NSColor, track: NSColor
            switch theme {
            case .howseen:
                let dark = isDarkAppearance
                fill = dark ? Howseen.ink.withAlphaComponent(0.96) : NSColor.white.withAlphaComponent(0.97)
                border = dark ? Howseen.inkBorder : Howseen.border
                bar = Howseen.blue
                dot = mode == .transcribing ? Howseen.sky : (dark ? Howseen.blue : Howseen.deep)
                track = dark ? Howseen.inkBorder : Howseen.track
            case .dark:
                fill = NSColor.black.withAlphaComponent(0.78)
                border = nil
                bar = NSColor.white.withAlphaComponent(0.92)
                dot = mode == .transcribing ? Howseen.sky : Howseen.blue
                track = NSColor.white.withAlphaComponent(0.18)
            }
            fill.setFill(); capsule.fill()
            if let border = border { border.setStroke(); capsule.lineWidth = 1; capsule.stroke() }

            // état à gauche : disque plein = écoute, anneau = mains libres, disque pulsé = transcription
            let d = 7 * scale
            let dotRect = NSRect(x: 12 * scale, y: bounds.midY - d / 2, width: d, height: d)
            let dotPath = NSBezierPath(ovalIn: dotRect)
            switch mode {
            case .listening: dot.setFill(); dotPath.fill()
            case .handsFree: dot.setStroke(); dotPath.lineWidth = 1.8 * scale; dotPath.stroke()
            case .transcribing:
                dot.withAlphaComponent(0.55 + 0.45 * CGFloat(abs(sin(phase)))).setFill(); dotPath.fill()
            }

            // barres de niveau sur un "track" discret, coins arrondis, aucune couleur d'alerte
            let startX = 28 * scale
            let w = 5 * scale, gap = 3.2 * scale
            let maxH = bounds.height - 14 * scale
            for (i, l) in levels.enumerated() {
                let x = startX + CGFloat(i) * (w + gap)
                let trackRect = NSRect(x: x, y: bounds.midY - maxH / 2, width: w, height: maxH)
                track.setFill(); NSBezierPath(roundedRect: trackRect, xRadius: w / 2, yRadius: w / 2).fill()
                let h: CGFloat
                if mode == .transcribing {
                    h = 4 * scale + (maxH - 4 * scale) * 0.55 * CGFloat(abs(sin(phase + Double(i) * 0.55)))
                } else {
                    h = max(3 * scale, CGFloat(l) * maxH)
                }
                bar.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: bounds.midY - h / 2, width: w, height: h), xRadius: w / 2, yRadius: w / 2).fill()
            }

            // petit logo Howseen à droite (« fait par Howseen »), visible dans les deux thèmes
            if let mark = BarsView.mark {
                let s = 26 * scale
                let rect = NSRect(x: bounds.maxX - s - 8 * scale, y: bounds.midY - s / 2, width: s, height: s)
                mark.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.95)
            }
        }

        static let mark: NSImage? = {
            guard let url = Bundle.main.url(forResource: "howseen-mark", withExtension: "png") else { return nil }
            return NSImage(contentsOf: url)
        }()
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
