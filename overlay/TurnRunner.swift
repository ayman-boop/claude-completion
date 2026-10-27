// Floating, always-on-top runner for Claude Code turns.
// Reads ~/.claude/turn-runner/state.json, written by the turn-runner mod.
// Settings live in ~/.claude/turn-runner/config.json; right-click the card to change them.
import AppKit

let home = NSString(string: "~/.claude/turn-runner").expandingTildeInPath
let statePath = home + "/state.json"
let configPath = home + "/config.json"
let dropPath = home + "/drop.wav"

struct RunState: Decodable {
    let startedAt: Double
    let tools: Int
    let endedAt: Double?
    let reason: String?
    let project: String?
}

struct Config: Codable {
    var runner = "🏃"
    var flipRunner = true          // most emoji face left; flip so they run toward the flag
    var finish = "🏁"
    var sound = "Water drop"       // "Water drop", a /System/Library/Sounds name, or "None"
    var volume: Float = 0.8
    var size = 1.0
    var hideAfter: Double = 10     // seconds the finish stays up; 0 keeps it until clicked
    var editor = "Visual Studio Code"

    init() {}
    // every field optional in the file, so a hand-edited config with gaps still loads
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let base = Config()
        runner = (try? c.decode(String.self, forKey: .runner)) ?? base.runner
        flipRunner = (try? c.decode(Bool.self, forKey: .flipRunner)) ?? base.flipRunner
        finish = (try? c.decode(String.self, forKey: .finish)) ?? base.finish
        sound = (try? c.decode(String.self, forKey: .sound)) ?? base.sound
        volume = (try? c.decode(Float.self, forKey: .volume)) ?? base.volume
        size = (try? c.decode(Double.self, forKey: .size)) ?? base.size
        hideAfter = (try? c.decode(Double.self, forKey: .hideAfter)) ?? base.hideAfter
        editor = (try? c.decode(String.self, forKey: .editor)) ?? base.editor
    }

    static func load() -> Config {
        guard let data = FileManager.default.contents(atPath: configPath),
              let c = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return c
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? enc.encode(self).write(to: URL(fileURLWithPath: configPath))
    }
}

let baseSize = NSSize(width: 340, height: 74)

final class TrackView: NSView {
    var state: RunState?
    var config = Config()
    var shown: Double = 0       // eased progress actually drawn
    var frameNo = 0
    var onClick: (() -> Void)?

    // A drag moves the card; only a press released without dragging counts as a click.
    var dragged = false
    override func mouseDown(with event: NSEvent) { dragged = false }
    override func mouseDragged(with event: NSEvent) {
        if !dragged { dragged = true; window?.performDrag(with: event) }
    }
    override func mouseUp(with event: NSEvent) { if !dragged { onClick?() } }

    func target(now: Double) -> Double {
        guard let s = state else { return 0 }
        if s.endedAt != nil { return 1 }
        let effort = (now - s.startedAt) / 60_000 + Double(s.tools) * 0.08
        return min(0.95, 1 - exp(-effort))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let s = state else { return }
        let scale = NSAffineTransform(); scale.scale(by: CGFloat(config.size)); scale.concat()

        let now = Date().timeIntervalSince1970 * 1000
        let done = s.endedAt != nil
        let ok = s.reason == nil || s.reason == "answer"
        let accent: NSColor = done ? (ok ? .systemGreen : .systemRed) : .systemYellow

        let left: CGFloat = 22, right = baseSize.width - 30, y: CGFloat = 26
        let x = left + CGFloat(shown) * (right - left)

        // track: dotted remainder, solid run so far
        let rest = NSBezierPath(); rest.move(to: NSPoint(x: x, y: y)); rest.line(to: NSPoint(x: right, y: y))
        rest.setLineDash([2, 4], count: 2, phase: 0); rest.lineWidth = 2
        NSColor.white.withAlphaComponent(0.35).setStroke(); rest.stroke()
        let ran = NSBezierPath(); ran.move(to: NSPoint(x: left, y: y)); ran.line(to: NSPoint(x: x, y: y))
        ran.lineWidth = 3; ran.lineCapStyle = .round; accent.setStroke(); ran.stroke()

        let emoji: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20)]
        (config.finish as NSString).draw(at: NSPoint(x: right - 2, y: y - 6), withAttributes: emoji)

        let runner = done ? (ok ? "🙌" : "🛑") : config.runner
        let bob: CGFloat = done ? 0 : (frameNo % 4 < 2 ? 3 : 0)
        let flip = !done && config.flipRunner
        if flip {
            let face = NSAffineTransform()
            face.translateX(by: x, yBy: 0); face.scaleX(by: -1, yBy: 1); face.translateX(by: -x, yBy: 0)
            NSGraphicsContext.saveGraphicsState(); face.concat()
        }
        (runner as NSString).draw(at: NSPoint(x: x - 11, y: y - 6 + bob), withAttributes: emoji)
        if flip { NSGraphicsContext.restoreGraphicsState() }

        let secs = Int(((s.endedAt ?? now) - s.startedAt) / 1000)
        let time = String(format: "%d:%02d", secs / 60, secs % 60)
        let name = s.project.map { ($0 as NSString).lastPathComponent } ?? "Claude"
        let label = done ? (ok ? "\(name) · finished · \(time)" : "\(name) · stopped (\(s.reason ?? "")) · \(time)")
                         : "\(name) · working · \(time) · \(s.tools) steps"
        let text: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: done ? accent : NSColor.white.withAlphaComponent(0.8),
        ]
        (label as NSString).draw(at: NSPoint(x: left, y: 50), withAttributes: text)
    }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var panel: NSPanel!
    var blur: NSVisualEffectView!
    let track = TrackView()
    var config = Config.load()
    var lastStart: Double = 0
    var dismissedStart: Double = -1
    var chimedStart: Double = -1

    func applicationDidFinishLaunching(_ n: Notification) {
        if !FileManager.default.fileExists(atPath: configPath) { config.save() }
        let screen = NSScreen.main?.visibleFrame ?? .zero
        panel = NSPanel(contentRect: NSRect(x: screen.maxX - baseSize.width - 16, y: screen.maxY - baseSize.height - 12,
                                            width: baseSize.width, height: baseSize.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("TurnRunnerPanel")

        blur = NSVisualEffectView()
        blur.material = .hudWindow; blur.blendingMode = .behindWindow; blur.state = .active
        blur.wantsLayer = true; blur.layer?.cornerRadius = 14; blur.layer?.masksToBounds = true
        blur.addSubview(track)
        panel.contentView = blur

        track.onClick = { [weak self] in self?.clicked() }
        let menu = NSMenu(); menu.delegate = self
        track.menu = menu
        apply()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.tick() }
    }

    // Size and the drawing follow the config; re-read it so hand edits take effect too.
    func apply() {
        track.config = config
        let size = NSSize(width: baseSize.width * config.size, height: baseSize.height * config.size)
        if panel.frame.size != size {
            let top = panel.frame.maxY
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
        }
        blur.frame = NSRect(origin: .zero, size: size)
        track.frame = blur.bounds
        track.needsDisplay = true
    }

    func update(_ change: (inout Config) -> Void) {
        change(&config); config.save(); apply()
    }

    // Left click: jump to the project in the editor; a finished card also goes away.
    func clicked() {
        if let project = track.state?.project {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-a", config.editor, project]
            try? open.run()
        }
        if track.state?.endedAt != nil { dismissedStart = lastStart; hide() }
    }

    func hide() { if panel.isVisible { panel.orderOut(nil) } }

    func play(_ name: String) {
        let sound: NSSound?
        switch name {
        case "None": return
        case "Water drop": sound = NSSound(contentsOfFile: dropPath, byReference: true)
        default: sound = NSSound(named: NSSound.Name(name))
        }
        sound?.volume = config.volume
        sound?.play()
    }

    func tick() {
        guard let data = FileManager.default.contents(atPath: statePath),
              let s = try? JSONDecoder().decode(RunState.self, from: data) else { hide(); return }
        let now = Date().timeIntervalSince1970 * 1000
        if s.startedAt != lastStart {
            lastStart = s.startedAt; track.shown = 0
            config = Config.load(); apply()
        }
        track.state = s

        // play the sound once per run, only for a finish seen live (not a stale file at launch)
        if let end = s.endedAt, chimedStart != s.startedAt, now - end < 5000 {
            chimedStart = s.startedAt
            play(config.sound)
        }

        let stale = s.endedAt == nil && now - s.startedAt > 3 * 3600 * 1000
        let finishedLongAgo = s.endedAt.map { config.hideAfter > 0 && now - $0 > config.hideAfter * 1000 } ?? false
        if stale || finishedLongAgo || dismissedStart == s.startedAt { hide(); return }

        track.frameNo += 1
        track.shown += (track.target(now: now) - track.shown) * (s.endedAt == nil ? 0.08 : 0.15)
        track.needsDisplay = true
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    // MARK: right-click settings menu, rebuilt each time so checkmarks match the config

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let project = track.state?.project {
            menu.addItem(item("Open \((project as NSString).lastPathComponent) in \(config.editor)") { [weak self] in self?.clicked() })
            menu.addItem(.separator())
        }
        menu.addItem(submenu("Runner", ["🏃", "🏃‍♀️", "🐎", "🐕", "🐢", "🐇", "🚴", "🦖", "🐌"], config.runner) { v in
            self.update { $0.runner = v } })
        menu.addItem(item("Flip runner direction", on: config.flipRunner) { [weak self] in
            self?.update { $0.flipRunner.toggle() } })
        menu.addItem(submenu("Finish line", ["🏁", "🏆", "🎉", "🍕", "☕️", "⭐️"], config.finish) { v in
            self.update { $0.finish = v } })

        let systemSounds = ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? [])
            .filter { $0.hasSuffix(".aiff") }.map { ($0 as NSString).deletingPathExtension }.sorted()
        menu.addItem(submenu("Sound", ["Water drop"] + systemSounds + ["None"], config.sound) { v in
            self.update { $0.sound = v }; self.play(v) })
        menu.addItem(submenu("Volume", ["Quiet", "Medium", "Loud"],
                             config.volume < 0.4 ? "Quiet" : config.volume < 0.9 ? "Medium" : "Loud") { v in
            self.update { $0.volume = ["Quiet": 0.3, "Medium": 0.7, "Loud": 1.0][v] ?? 0.7 }; self.play(self.config.sound) })
        menu.addItem(submenu("Size", ["Small", "Medium", "Large"],
                             config.size < 0.9 ? "Small" : config.size < 1.2 ? "Medium" : "Large") { v in
            self.update { $0.size = ["Small": 0.8, "Medium": 1.0, "Large": 1.35][v] ?? 1.0 } })
        let hides = ["5 seconds": 5.0, "10 seconds": 10, "30 seconds": 30, "Until clicked": 0]
        menu.addItem(submenu("Hide finish after", ["5 seconds", "10 seconds", "30 seconds", "Until clicked"],
                             hides.first { $0.value == config.hideAfter }?.key ?? "") { v in
            self.update { $0.hideAfter = hides[v] ?? 10 } })
        menu.addItem(submenu("Open project in", ["Visual Studio Code", "Cursor", "Windsurf", "Zed", "Terminal", "iTerm"], config.editor) { v in
            self.update { $0.editor = v } })
        menu.addItem(.separator())
        menu.addItem(item("Edit config.json…") { NSWorkspace.shared.open(URL(fileURLWithPath: configPath)) })
        menu.addItem(item("Hide for now") { [weak self] in self.map { $0.dismissedStart = $0.lastStart; $0.hide() } })
        menu.addItem(item("Quit Turn Runner") { NSApp.terminate(nil) })
    }

    final class Action: NSObject { let run: () -> Void; init(_ r: @escaping () -> Void) { run = r }
        @objc func fire() { run() } }

    func item(_ title: String, on: Bool = false, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = Action(run)
        let i = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        i.target = a; i.representedObject = a; i.state = on ? .on : .off
        return i
    }

    func submenu(_ title: String, _ options: [String], _ current: String, _ pick: @escaping (String) -> Void) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for o in options { sub.addItem(item(o, on: o == current) { pick(o) }) }
        parent.submenu = sub
        return parent
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
