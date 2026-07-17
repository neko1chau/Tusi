import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var hotkey: HotkeyManager?

    let settings = SettingsStore()
    let panelState = PanelState()
    lazy var engine = TranslationEngine(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        panelController = PanelController(
            engine: engine,
            settings: settings,
            panelState: panelState,
            statusItem: statusItem
        )
        hotkey = HotkeyManager { [weak self] in
            self?.togglePanel()
        }

        // First run without a usable profile: open the panel so setup is obvious.
        if !settings.isConfigured {
            panelController.show()
        }

        // Debug preview: TUSI_PREVIEW=main|settings pins the panel open with sample content.
        if let preview = ProcessInfo.processInfo.environment["TUSI_PREVIEW"] {
            if ProcessInfo.processInfo.environment["TUSI_DARK"] != nil {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            panelState.pinned = true
            panelController.show()
            switch preview {
            case "settings":
                settings.profiles = [
                    APIProfile(baseURL: "https://api.deepseek.com", apiKey: "sk-preview", model: "deepseek-chat"),
                    APIProfile(baseURL: "https://openrouter.ai/api/v1", apiKey: "sk-preview", model: "deepseek/deepseek-chat"),
                ]
                panelState.showSettings = true
            case "empty":
                panelState.showSettings = false
            case "quotetest":
                settings.profiles = [
                    APIProfile(baseURL: "http://127.0.0.1:8806/v1", apiKey: "sk-x", model: "m"),
                    APIProfile(),
                ]
                settings.autoCopy = true
                panelState.showSettings = false
                engine.input = "测试引号"
                engine.translate()
            case "corners":
                // Opens settings on a delay so a screenshot burst can catch the
                // transition mid-flight; pair with TUSI_SLOWMO to stretch it out.
                engine.debugPreview(
                    input: "得益于全新的架构，这次更新带来了显著的性能提升。",
                    output: "Thanks to the brand-new architecture, this update delivers a significant performance boost.",
                    toast: nil
                )
                panelState.showSettings = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.snappy(duration: 0.25 * Theme.animationScale)) {
                        self.panelState.showSettings = true
                    }
                }
            case "reopen":
                panelState.showSettings = false
                engine.debugPreview(
                    input: "得益于全新的架构，这次更新带来了显著的性能提升。",
                    output: "Thanks to the brand-new architecture, this update delivers a significant performance boost.",
                    toast: nil
                )
                panelController.show()
            case "falltest":
                // Primary points at a server that 401s, backup at one that works.
                settings.profiles = [
                    APIProfile(baseURL: "http://127.0.0.1:8801/v1", apiKey: "sk-x", model: "broken-model"),
                    APIProfile(baseURL: "http://127.0.0.1:8802/v1", apiKey: "sk-x", model: "backup-model"),
                ]
                panelState.showSettings = false
                engine.input = "这句话应该由备用供应商翻译。"
                engine.translate()
            default:
                panelState.showSettings = false
                engine.debugPreview(
                    input: "得益于全新的架构，这次更新带来了显著的性能提升，同时保持了完全的向后兼容。",
                    output: "Thanks to the brand-new architecture, this update delivers a significant performance boost while remaining fully backward compatible.",
                    toast: preview == "fallback" ? .fellBack : nil
                )
            }
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Tusi")
                ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Tusi")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return togglePanel() }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开翻译面板", action: #selector(openPanel), keyEquivalent: " ")
        openItem.keyEquivalentModifierMask = [.option]
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Tusi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanel() {
        panelController.show()
    }

    @objc private func openSettings() {
        panelState.showSettings = true
        panelController.show()
    }

    private func togglePanel() {
        panelController.toggle()
    }

    // MARK: - Main menu (needed so ⌘C/⌘V/⌘Z work in a menu-bar-only app)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 Tusi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
