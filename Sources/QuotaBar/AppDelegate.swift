import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var reader = UsageReader(settings: settings)
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var snapshot = UsageSnapshot.empty

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }

    // MARK: - Actions

    @objc private func refresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.snapshot = await self.reader.read()
            self.renderStatusItem()
            self.configureMenu()
        }
    }

    @objc private func setTextMode()       { settings.displayMode = .text; update() }
    @objc private func setRingMode()       { settings.displayMode = .ring; update() }
    @objc private func toggleRemaining()   { settings.showRemaining.toggle(); update() }
    @objc private func toggleClaude()      { settings.showClaude.toggle(); update() }
    @objc private func toggleCodex()       { settings.showCodex.toggle(); update() }
    @objc private func quit()              { NSApp.terminate(nil) }

    private func update() { renderStatusItem(); configureMenu() }

    // MARK: - Path / limit settings

    @objc private func setClaudePath() {
        prompt(title: "Claude 项目目录",
               message: "留空恢复默认（~/.claude/projects）\n也可填父目录，会自动递归查找 .jsonl 文件",
               placeholder: "~/.claude/projects",
               current: settings.claudeProjectsPath) { [weak self] v in
            self?.settings.claudeProjectsPath = v
            self?.refresh()
        }
    }

    @objc private func setCodexPath() {
        prompt(title: "Codex 会话目录",
               message: "留空恢复默认（~/.codex/sessions）\n也可填父目录，会自动递归查找 .jsonl 文件",
               placeholder: "~/.codex/sessions",
               current: settings.codexSessionsPath) { [weak self] v in
            self?.settings.codexSessionsPath = v
            self?.refresh()
        }
    }

    @objc private func setTokenLimit() {
        prompt(title: "Claude Token 上限（5h 窗口）",
               message: "Claude Code 5小时滚动窗口的 token 预算\n（input + output + cache创建 之和）",
               placeholder: "100000",
               current: settings.claudeTokenLimit == 100_000 ? nil
                   : "\(settings.claudeTokenLimit)") { [weak self] v in
            if let v, let n = Int(v), n > 0 {
                self?.settings.claudeTokenLimit = n
            } else {
                self?.settings.claudeTokenLimit = 100_000
            }
            self?.refresh()
        }
    }

    // MARK: - Render

    private func renderStatusItem() {
        guard let button = statusItem?.button else { return }

        switch settings.displayMode {
        case .text:
            button.image = nil
            button.title = ""
            button.attributedTitle = buildStatusText()
            statusItem?.length = NSStatusItem.variableLength

        case .ring:
            button.title = ""
            button.image = StatusIcon.makeRingImage(
                snapshot: snapshot,
                showClaude: settings.showClaude,
                showCodex: settings.showCodex
            )
            button.imagePosition = .imageOnly
            statusItem?.length = StatusIcon.ringItemLength(
                showClaude: settings.showClaude,
                showCodex: settings.showCodex
            )
        }
        button.toolTip = snapshot.tooltip
    }

    private func buildStatusText() -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let result = NSMutableAttributedString()
        var added = false

        if settings.showClaude {
            result.append(textLabel("C", usage: snapshot.claude, font: font))
            added = true
        }
        if settings.showCodex {
            if added { result.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            result.append(textLabel("X", usage: snapshot.codex, font: font))
            added = true
        }
        if !added {
            result.append(NSAttributedString(string: "--",
                attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return result
    }

    private func textLabel(_ prefix: String, usage: ProviderUsage, font: NSFont) -> NSAttributedString {
        let (value, color): (String, NSColor)
        if settings.showRemaining {
            let rem = usage.percent.map { max(0.0, 100.0 - $0) }
            value = rem.map { "\(Int($0.rounded()))%" } ?? "--%"
            color = rem.map { StatusIcon.remainingColor($0) } ?? .secondaryLabelColor
        } else {
            value = usage.shortLabel
            color = StatusIcon.usageColor(usage.percent)
        }
        return NSAttributedString(string: "\(prefix) \(value)",
                                  attributes: [.font: font, .foregroundColor: color])
    }

    // MARK: - Menu

    private func configureMenu() {
        let menu = NSMenu()

        let summary = NSMenuItem(title: snapshot.menuTitle, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())

        let claudeItem = NSMenuItem(title: snapshot.claude.menuLine(prefix: "Claude"), action: nil, keyEquivalent: "")
        claudeItem.isEnabled = false
        menu.addItem(claudeItem)

        let codexItem = NSMenuItem(title: snapshot.codex.menuLine(prefix: "Codex"), action: nil, keyEquivalent: "")
        codexItem.isEnabled = false
        menu.addItem(codexItem)

        menu.addItem(.separator())

        // Display mode
        let textMode = NSMenuItem(title: "文字模式", action: #selector(setTextMode), keyEquivalent: "")
        textMode.target = self
        textMode.state = settings.displayMode == .text ? .on : .off
        menu.addItem(textMode)

        let ringMode = NSMenuItem(title: "图标环模式", action: #selector(setRingMode), keyEquivalent: "")
        ringMode.target = self
        ringMode.state = settings.displayMode == .ring ? .on : .off
        menu.addItem(ringMode)

        if settings.displayMode == .text {
            let rem = NSMenuItem(title: settings.showRemaining ? "当前：剩余量" : "当前：使用量",
                                 action: #selector(toggleRemaining), keyEquivalent: "")
            rem.target = self
            menu.addItem(rem)
        }

        menu.addItem(.separator())

        let showClaude = NSMenuItem(title: "显示 Claude", action: #selector(toggleClaude), keyEquivalent: "")
        showClaude.target = self
        showClaude.state = settings.showClaude ? .on : .off
        menu.addItem(showClaude)

        let showCodex = NSMenuItem(title: "显示 Codex", action: #selector(toggleCodex), keyEquivalent: "")
        showCodex.target = self
        showCodex.state = settings.showCodex ? .on : .off
        menu.addItem(showCodex)

        menu.addItem(.separator())

        // Config submenu
        let configItem = NSMenuItem(title: "配置数据源…", action: nil, keyEquivalent: "")
        let configSub = NSMenu()

        let claudePath = NSMenuItem(title: "Claude 项目路径…", action: #selector(setClaudePath), keyEquivalent: "")
        claudePath.target = self
        configSub.addItem(claudePath)

        let codexPath = NSMenuItem(title: "Codex 会话路径…", action: #selector(setCodexPath), keyEquivalent: "")
        codexPath.target = self
        configSub.addItem(codexPath)

        let tokenLimit = NSMenuItem(title: "Claude Token 上限…", action: #selector(setTokenLimit), keyEquivalent: "")
        tokenLimit.target = self
        configSub.addItem(tokenLimit)

        configItem.submenu = configSub
        menu.addItem(configItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "退出 QuotaBar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Generic prompt helper

    private func prompt(title: String, message: String, placeholder: String,
                        current: String?, apply: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "重置默认")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = placeholder
        field.stringValue = current ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        switch alert.runModal() {
        case .alertFirstButtonReturn:  apply(field.stringValue.isEmpty ? nil : field.stringValue)
        case .alertSecondButtonReturn: apply(nil)
        default: break
        }
    }
}
