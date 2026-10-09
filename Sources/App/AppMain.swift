import Cocoa
import AVFoundation

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // pas d'icône Dock
        app.run()
    }

    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyMonitor()
    private let recorder = Recorder()
    private let overlay = Overlay()
    private let copyPopup = CopyPopup()
    private var pipeline: DictationPipeline?
    private var config = Config.load()
    private var history = History(limit: 50)
    private var state: State = .loading { didSet { updateIcon() } }
    private var permissionsOK = false
    private var configWatcher: DispatchSourceFileSystemObject?

    enum State { case loading, ready, listening, transcribing, error(String) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureDirs()
        Log.info("=== Dictee démarre (pid \(ProcessInfo.processInfo.processIdentifier)) ===")
        history = History.load(limit: config.historySize)
        setupStatusItem()
        Permissions.request()

        // chargement du modèle en arrière-plan, l'app reste réactive
        let modelPath = Paths.modelsDir.appendingPathComponent(config.model).path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard FileManager.default.fileExists(atPath: modelPath) else {
                DispatchQueue.main.async {
                    self.state = .error("Modèle manquant")
                    self.alert("Modèle Whisper introuvable",
                               "Fichier attendu : \(modelPath)\n\nLance ./install.sh (ou scripts/download-model.sh) pour le télécharger.")
                }
                return
            }
            do {
                let t0 = Date()
                let engine = try WhisperEngine(modelPath: modelPath)
                let p = DictationPipeline(config: self.config, engine: engine)
                // préchauffage : premier appel Metal compilé d'avance
                _ = engine.transcribe([Float](repeating: 0, count: 16000), options: .init())
                Log.info(String(format: "Modèle %@ chargé et préchauffé en %.1f s", self.config.model, Date().timeIntervalSince(t0)))
                DispatchQueue.main.async {
                    self.pipeline = p
                    self.state = .ready
                    self.startHotkey()
                }
            } catch {
                Log.error("Chargement modèle : \(error.localizedDescription)")
                DispatchQueue.main.async { self.state = .error(error.localizedDescription) }
            }
        }
        watchConfigDir()
    }

    private func startHotkey() {
        permissionsOK = Permissions.check().allGranted
        hotkey.maxHoldAsTap = Double(config.maxHoldAsTapMs) / 1000
        hotkey.doubleTapWindow = Double(config.doubleTapMs) / 1000
        hotkey.onEvent = { [weak self] e in self?.handleHotkey(e) }
        if !hotkey.start() {
            state = .error("Autorisations")
            _ = Permissions.explainIfMissing()
            // on réessaie toutes les 5 s : dès que l'autorisation est donnée, ça part
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] t in
                guard let self = self else { t.invalidate(); return }
                if self.hotkey.isRunning { t.invalidate(); return }
                if self.hotkey.start() { self.state = .ready; t.invalidate() }
            }
        } else if !Permissions.check().allGranted {
            _ = Permissions.explainIfMissing()
        }
    }

    // MARK: - Dictée

    private var currentApp: (bundleId: String?, name: String?) = (nil, nil)

    private func handleHotkey(_ e: HotkeyMonitor.Event) {
        switch e {
        case .start(let handsFree):
            guard pipeline != nil, case .ready = state else { return }
            currentApp = Paster.frontmostApp()
            do {
                try recorder.start(micName: config.micName)
            } catch {
                Log.error("Micro : \(error.localizedDescription)")
                state = .error("Micro")
                _ = Permissions.explainIfMissing()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.state = .ready }
                return
            }
            recorder.onLevel = { [weak self] l in self?.overlay.level(l) }
            overlay.show(.listening(handsFree: handsFree), config: config.overlay)
            if config.sounds { Sounds.start() }
            state = .listening
        case .cancel:
            recorder.cancel()
            overlay.hide()
            if case .listening = state { state = .ready }
            Log.info("Dictée annulée")
        case .stop:
            guard case .listening = state else { return }
            let samples = recorder.stop()
            if config.sounds { Sounds.stop() }
            guard Double(samples.count) / 16000.0 >= 0.4 else { overlay.hide(); state = .ready; return }
            overlay.show(.transcribing, config: config.overlay)
            state = .transcribing
            let app = currentApp
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.transcribeAndPaste(samples: samples, app: app)
            }
        }
    }

    private func transcribeAndPaste(samples: [Float], app: (bundleId: String?, name: String?)) {
        guard let pipeline = pipeline else { return }
        let out = pipeline.process(samples: samples, appBundle: app.bundleId)
        Log.info(String(format: "Dictée %.1f s → %.2f s [%@] app=%@ : %@",
                        out.audioSeconds, out.totalSeconds, out.language, app.bundleId ?? "?", out.text))
        DispatchQueue.main.async {
            self.overlay.hide()
            self.state = .ready
            guard !out.text.isEmpty else { return }
            // Comme Wispr Flow : pas de champ de texte actif → on ne colle pas à l'aveugle, on propose de copier.
            if Paster.hasEditableFocus() == false {
                Log.info("Pas de champ de texte actif : fenêtre Copier")
                self.copyPopup.show(text: out.text, theme: self.config.overlay.theme)
            } else {
                Paster.paste(out.text, method: self.config.style(for: app.bundleId).pasteMethod ?? "paste")
            }
            self.history.add(HistoryEntry(date: ISO8601DateFormatter().string(from: Date()), text: out.text, raw: out.raw,
                                          app: app.bundleId, language: out.language,
                                          audioSeconds: out.audioSeconds, latencySeconds: out.totalSeconds))
            self.rebuildMenu()
            self.scheduleLearning(pasted: out.text, app: app.bundleId)
        }
    }

    /// Apprentissage façon Wispr : relecture du champ via AX quelques secondes après le collage.
    private func scheduleLearning(pasted: String, app: String?) {
        guard config.learning.enabled, permissionsOK || AXIsProcessTrusted() else { return }
        let delay = config.learning.delaySeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, let pipeline = self.pipeline else { return }
            // seulement si l'utilisateur est resté dans la même app
            guard Paster.frontmostApp().bundleId == app else { return }
            guard let observed = Paster.focusedFieldText(), !observed.isEmpty else { return }
            DispatchQueue.global(qos: .utility).async {
                let promoted = pipeline.learn(pasted: pasted, observed: observed)
                guard !promoted.isEmpty else { return }
                DispatchQueue.main.async {
                    self.notify("Dictionnaire mis à jour",
                                promoted.map { "« \($0.original) » → « \($0.corrected) »" }.joined(separator: "\n"))
                }
            }
        }
    }

    // MARK: - Barre de menus

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        rebuildMenu()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let (symbol, desc): (String, String)
        switch state {
        case .loading: (symbol, desc) = ("hourglass", "Chargement du modèle…")
        case .ready: (symbol, desc) = ("mic", "Prêt — maintiens fn pour dicter")
        case .listening: (symbol, desc) = ("mic.fill", "Écoute…")
        case .transcribing: (symbol, desc) = ("waveform", "Transcription…")
        case .error(let e): (symbol, desc) = ("mic.slash", "Erreur : \(e)")
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: desc)
        button.toolTip = "Dictee — \(desc)"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: statusTitle(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        // Historique
        if !history.entries.isEmpty {
            let histMenu = NSMenu()
            for (i, e) in history.entries.prefix(config.historySize).enumerated() {
                let preview = e.text.count > 56 ? String(e.text.prefix(56)) + "…" : e.text
                let item = NSMenuItem(title: preview.replacingOccurrences(of: "\n", with: " "), action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                item.target = self; item.tag = i
                item.toolTip = e.text
                histMenu.addItem(item)
            }
            let hist = NSMenuItem(title: "Historique (cliquer = copier)", action: nil, keyEquivalent: "")
            menu.addItem(hist)
            menu.setSubmenu(histMenu, for: hist)
        } else {
            menu.addItem(NSMenuItem(title: "Historique vide", action: nil, keyEquivalent: ""))
        }

        // Micro
        let micMenu = NSMenu()
        let def = NSMenuItem(title: "Micro par défaut du système", action: #selector(pickMic(_:)), keyEquivalent: "")
        def.target = self; def.representedObject = nil as String?
        def.state = config.micName == nil ? .on : .off
        micMenu.addItem(def)
        for d in Recorder.inputDevices() {
            let item = NSMenuItem(title: d.name, action: #selector(pickMic(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = d.name
            item.state = config.micName == d.name ? .on : .off
            micMenu.addItem(item)
        }
        let mic = NSMenuItem(title: "Micro", action: nil, keyEquivalent: "")
        menu.addItem(mic)
        menu.setSubmenu(micMenu, for: mic)

        let sounds = NSMenuItem(title: "Sons début/fin", action: #selector(toggleSounds), keyEquivalent: "")
        sounds.target = self; sounds.state = config.sounds ? .on : .off
        menu.addItem(sounds)
        let learn = NSMenuItem(title: "Apprentissage des corrections", action: #selector(toggleLearning), keyEquivalent: "")
        learn.target = self; learn.state = config.learning.enabled ? .on : .off
        menu.addItem(learn)

        menu.addItem(.separator())
        menu.addItem(withTarget: self, title: "Ouvrir le dictionnaire", action: #selector(openDictionary))
        menu.addItem(withTarget: self, title: "Ouvrir la config", action: #selector(openConfig))
        menu.addItem(withTarget: self, title: "Ouvrir les logs", action: #selector(openLogs))
        menu.addItem(withTarget: self, title: "Recharger la config", action: #selector(reloadConfig))
        menu.addItem(.separator())
        menu.addItem(withTarget: self, title: "Vérifier les autorisations…", action: #selector(checkPermissions))
        menu.addItem(withTarget: self, title: "Relancer", action: #selector(relaunch))
        menu.addItem(withTarget: self, title: "Fait par Howseen · howseen.ai", action: #selector(openHowseen))
        menu.addItem(.separator())
        menu.addItem(withTarget: self, title: "Quitter Dictee", action: #selector(quit))
        statusItem.menu = menu
    }

    private func statusTitle() -> String {
        switch state {
        case .loading: return "Chargement du modèle…"
        case .ready: return "Prêt — fn : dicter, 2×fn : mains libres"
        case .listening: return "Écoute…"
        case .transcribing: return "Transcription…"
        case .error(let e): return "Erreur : \(e)"
        }
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard sender.tag < history.entries.count else { return }
        let pb = NSPasteboard.general
        pb.clearContents(); pb.setString(history.entries[sender.tag].text, forType: .string)
    }
    @objc private func pickMic(_ sender: NSMenuItem) {
        config.micName = sender.representedObject as? String
        try? config.save(); rebuildMenu()
    }
    @objc private func toggleSounds() { config.sounds.toggle(); try? config.save(); rebuildMenu() }
    @objc private func toggleLearning() { config.learning.enabled.toggle(); try? config.save(); pipeline?.reload(); rebuildMenu() }
    @objc private func openDictionary() { ensureConfigFiles(); NSWorkspace.shared.open(Paths.dictionaryFile) }
    @objc private func openConfig() { ensureConfigFiles(); NSWorkspace.shared.open(Paths.configFile) }
    @objc private func openLogs() { NSWorkspace.shared.open(Paths.logsDir) }
    @objc private func reloadConfig() {
        config = Config.load(); pipeline?.reload()
        hotkey.maxHoldAsTap = Double(config.maxHoldAsTapMs) / 1000
        hotkey.doubleTapWindow = Double(config.doubleTapMs) / 1000
        rebuildMenu()
    }
    @objc private func checkPermissions() {
        Permissions.request()
        if Permissions.explainIfMissing() {
            alert("Tout est bon", "Microphone, Accessibilité et Surveillance de l'entrée sont accordés.")
            if !hotkey.isRunning { startHotkey() }
        }
    }
    @objc private func relaunch() {
        // si on tourne sous launchd, kickstart relance proprement ; sinon open -n
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["kickstart", "-k", "gui/\(getuid())/local.dictee"]
        try? task.run(); task.waitUntilExit()
        if task.terminationStatus != 0 {
            let t = Process(); t.launchPath = "/usr/bin/open"; t.arguments = ["-n", Bundle.main.bundlePath]
            try? t.run()
            NSApp.terminate(nil)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openHowseen() {
        if let u = URL(string: "https://howseen.ai/?utm_source=dictee&utm_medium=app") { NSWorkspace.shared.open(u) }
    }

    /// Si les fichiers de config n'existent pas encore, on les crée depuis les modèles embarqués.
    private func ensureConfigFiles() {
        let fm = FileManager.default
        let defaults = Bundle.main.resourceURL?.appendingPathComponent("defaults")
        for (file, name) in [(Paths.configFile, "config.json"), (Paths.dictionaryFile, "dictionary.json"), (Paths.snippetsFile, "snippets.json")] {
            guard !fm.fileExists(atPath: file.path) else { continue }
            if let src = defaults?.appendingPathComponent(name), fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: file)
            } else {
                try? "{}".write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Recharge automatiquement quand un fichier de ~/.config/dictee change.
    private func watchConfigDir() {
        let fd = open(Paths.configDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in
            self?.debounceReload()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        configWatcher = src
    }
    private var reloadWork: DispatchWorkItem?
    private func debounceReload() {
        reloadWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.reloadConfig() }
        reloadWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
    private func notify(_ title: String, _ text: String) {
        // notification discrète via osascript (UserNotifications exige un bundle signé par un compte développeur)
        Log.info("\(title) : \(text.replacingOccurrences(of: "\n", with: " ; "))")
        let esc = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let script = "display notification \"\(esc(text))\" with title \"\(esc(title))\""
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }
}

private extension NSMenu {
    func addItem(withTarget target: AnyObject, title: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        addItem(item)
    }
}
