import AppKit
import ServiceManagement
import GeigerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    private lazy var scanner = TranscriptScanner(projectsDir: projectsDir)
    private let scanQueue = DispatchQueue(label: "claude-geiger.scan", qos: .utility)
    private var totalDose = 0
    private var projectsDirExists = true
    private var timers: [Timer] = []
    private var rateWindow = RateWindow()
    private var clickScheduler = ClickScheduler()
    private let audio = ClickAudio()
    private let started = Date()
    private var lastBurst: (project: String, tokens: Int, t: Date)?
    private var clickFlashUntil = Date.distantPast

    private let rateItem = NSMenuItem(title: "RATE  —", action: nil, keyEquivalent: "")
    private let doseItem = NSMenuItem(title: "DOSE  —", action: nil, keyEquivalent: "")
    private let lastItem = NSMenuItem(title: "LAST  —", action: nil, keyEquivalent: "")
    private var muteItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()

        let scanTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.scanTick() }
        let clickTimer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in self?.clickTick() }
        let renderTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.render() }
        // .common mode so timers keep firing while the menu is open
        timers = [scanTimer, clickTimer, renderTimer]
        for t in timers { RunLoop.main.add(t, forMode: .common) }
        render()
    }

    // MARK: ticks

    private func scanTick() {
        let now = Date()
        scanQueue.async { [weak self] in
            guard let self else { return }
            let bursts = self.scanner.scan(now: now)
            let dose = self.scanner.totalDose
            let dirExists = FileManager.default.fileExists(atPath: self.projectsDir.path)
            DispatchQueue.main.async {
                self.totalDose = dose
                self.projectsDirExists = dirExists
                for b in bursts {
                    self.rateWindow.add(tokens: b.tokens, at: now)
                    self.lastBurst = (b.project, b.tokens, now)
                }
            }
        }
    }

    private func clickTick() {
        let frac = gaugeFraction(rate: rateWindow.tokensPerMinute(now: Date()))
        if clickScheduler.tick(frac: frac, now: Date().timeIntervalSinceReferenceDate) {
            audio.click()
            clickFlashUntil = Date().addingTimeInterval(0.15)
        }
    }

    // MARK: rendering

    private func zoneColor(_ zone: ZoneLevel, flashing: Bool) -> NSColor {
        if flashing { return .systemOrange }
        switch zone {
        case .background: return .secondaryLabelColor
        case .elevated: return .systemGreen
        case .hot: return .systemYellow
        case .critical, .meltdown: return .systemRed
        }
    }

    private func fmt(_ n: Double) -> String {
        if n >= 1_000_000 { return String(format: "%.2f Mtok", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1f ktok", n / 1_000) }
        return "\(Int(n.rounded())) tok"
    }

    private func compactRate(_ n: Double) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM/m", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk/m", n / 1_000) }
        return String(format: "%.0f/m", n)
    }

    private func render() {
        let now = Date()
        let rate = rateWindow.tokensPerMinute(now: now)
        let zone = ZoneLevel.forRate(rate)
        let color = zoneColor(zone, flashing: now < clickFlashUntil)

        let title = zone == .background ? "☢" : "☢ \(compactRate(rate))"
        statusItem.button?.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            ])

        let uptime = Int(now.timeIntervalSince(started))
        let hh = String(format: "%02d", uptime / 3600)
        let mm = String(format: "%02d", (uptime % 3600) / 60)
        let ss = String(format: "%02d", uptime % 60)

        rateItem.title = "RATE  \(fmt(rate))/min   \(zone.label)"
        doseItem.title = "DOSE  \(fmt(Double(totalDose)))   uptime \(hh):\(mm):\(ss)"
        if let b = lastBurst, now.timeIntervalSince(b.t) < 30 {
            lastItem.title = "LAST  +\(fmt(Double(b.tokens)))  \(String(b.project.prefix(30)))"
        } else if !projectsDirExists {
            lastItem.title = "LAST  no transcripts found"
        } else {
            lastItem.title = "LAST  —"
        }
    }

    // MARK: menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in [rateItem, doseItem, lastItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        muteItem = NSMenuItem(
            title: "Clicks audible", action: #selector(toggleMute), keyEquivalent: "")
        muteItem.target = self
        muteItem.state = audio.muted ? .off : .on
        menu.addItem(muteItem)

        loginItem = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Claude Geiger", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleMute() {
        audio.muted.toggle()
        muteItem.state = audio.muted ? .off : .on
    }

    @objc private func toggleLaunchAtLogin() {
        // only works from inside a .app bundle; from a bare binary it throws
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("launch-at-login toggle failed: \(error)")
        }
        loginItem.state = service.status == .enabled ? .on : .off
    }
}
