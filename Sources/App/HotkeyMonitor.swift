import Cocoa

/// Capte la touche fn via un CGEventTap sur flagsChanged (+ Échap pendant une dictée).
///  - maintenir fn        → enregistre tant que la touche est tenue (push-to-talk)
///  - double-tap fn       → mode mains libres ; re-tap fn pour arrêter
///  - Échap               → annule la dictée en cours
final class HotkeyMonitor {
    enum Event { case start(handsFree: Bool), stop, cancel }
    var onEvent: ((Event) -> Void)?

    /// Réglages (ms)
    var maxHoldAsTap: TimeInterval = 0.30
    var doubleTapWindow: TimeInterval = 0.40

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    // état
    private var fnDown = false
    private var fnDownAt: Date?
    private var lastTapAt: Date?
    private var recording = false
    private var handsFree = false
    private var holdTimer: Timer?

    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            }, userInfo: selfPtr) else {
            Log.error("CGEventTap refusé : l'autorisation « Surveillance de l'entrée » (et/ou Accessibilité) manque")
            return false
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        Log.info("Écoute de la touche fn active")
        return true
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil; runLoopSource = nil; isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS désactive le tap s'il est trop lent : on le relance
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true); Log.warn("Event tap relancé après désactivation système") }
            return
        }
        if type == .keyDown {
            // Échap (53) pendant une dictée = annuler
            if recording, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                DispatchQueue.main.async { self.endRecording(cancelled: true) }
            }
            return
        }
        guard type == .flagsChanged else { return }
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let fnFlag = event.flags.contains(.maskSecondaryFn)
        // la touche fn seule : keycode 63 (kVK_Function). On ignore les flèches/F-keys qui portent aussi le flag fn.
        guard keycode == 63 else { return }
        DispatchQueue.main.async { self.fnChanged(down: fnFlag) }
    }

    private func fnChanged(down: Bool) {
        guard down != fnDown else { return }
        fnDown = down
        let now = Date()
        if down {
            fnDownAt = now
            if recording {
                if handsFree {
                    endRecording(cancelled: false)       // re-tap pendant le mode mains libres → stop
                } else if let last = lastTapAt, now.timeIntervalSince(last) <= doubleTapWindow {
                    handsFree = true                      // 2e tap dans la fenêtre → mains libres
                    holdTimer?.invalidate(); holdTimer = nil
                    Log.info("Mode mains libres")
                }
            } else {
                handsFree = false
                beginRecording()                          // appui = on enregistre tout de suite (push-to-talk)
            }
        } else {
            let heldFor = fnDownAt.map { now.timeIntervalSince($0) } ?? 0
            let wasTap = heldFor <= maxHoldAsTap
            lastTapAt = wasTap ? now : nil
            guard recording else { return }
            if handsFree { return }                       // les relâchements n'arrêtent pas le mode mains libres
            if wasTap {
                // appui bref : on attend un éventuel 2e tap ; sinon dictée trop courte → annulée
                holdTimer?.invalidate()
                holdTimer = Timer.scheduledTimer(withTimeInterval: doubleTapWindow + 0.05, repeats: false) { [weak self] _ in
                    guard let self = self, self.recording, !self.handsFree, !self.fnDown else { return }
                    self.endRecording(cancelled: true)
                }
            } else {
                endRecording(cancelled: false)            // fin du push-to-talk → transcrire
            }
        }
    }

    private var recordingStartedAt: Date?
    private func beginRecording() {
        recording = true
        recordingStartedAt = Date()
        onEvent?(.start(handsFree: handsFree))
    }
    private func endRecording(cancelled: Bool) {
        holdTimer?.invalidate(); holdTimer = nil
        recording = false
        let hf = handsFree
        handsFree = false
        recordingStartedAt = nil
        _ = hf
        onEvent?(cancelled ? .cancel : .stop)
    }
}
