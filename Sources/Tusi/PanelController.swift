import AppKit
import SwiftUI

/// Borderless floating panel that can receive keyboard input.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    static let panelWidth: CGFloat = 424

    private let panel: FloatingPanel
    private let engine: TranslationEngine
    private let settings: SettingsStore
    private let panelState: PanelState
    private weak var statusItem: NSStatusItem?

    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var desiredHeight: CGFloat = 160
    private var hasShownOnce = false

    init(engine: TranslationEngine, settings: SettingsStore, panelState: PanelState, statusItem: NSStatusItem?) {
        self.engine = engine
        self.settings = settings
        self.panelState = panelState
        self.statusItem = statusItem

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 160),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        let root = RootView(onHeightChange: { [weak self] height in
            self?.setContentHeight(height)
        })
        .environmentObject(engine)
        .environmentObject(settings)
        .environmentObject(panelState)

        let container = PanelContainerView(cornerRadius: Theme.cornerRadius)
        container.frame = panel.contentRect(forFrameRect: panel.frame)
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: root)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        installKeyMonitor()
        installResignObserver()
    }

    // MARK: - Show / hide

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        position()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.animator().alphaValue = 1

        if !hasShownOnce {
            hasShownOnce = true
            if !settings.isConfigured {
                panelState.showSettings = true
            }
        }
        // Reopening on a finished translation means the last text is spent — preselect it
        // so the next keystroke starts a new one, without destroying an unfinished draft.
        let selectAll = engine.hasFinishedTranslation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .tusiFocusInput, object: nil)
            guard selectAll else { return }
            // One more hop: the focus above lands via SwiftUI's @FocusState, which
            // only takes effect on the next runloop pass.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                (self.panel.firstResponder as? NSTextView)?.selectAll(nil)
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        NSApp.hide(nil)
    }

    private func position() {
        let width = Self.panelWidth
        let height = desiredHeight

        // Show on the screen the user is actually on (where the mouse is),
        // top-centered just below the menu bar — Spotlight-style. This stays
        // correct even when the status icon is hidden by a crowded menu bar.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        var x = visible.midX - width / 2

        // If the status icon is visible on this screen, anchor under it instead.
        if let buttonWindow = statusItem?.button?.window,
           buttonWindow.screen == screen,
           screen.frame.intersects(buttonWindow.frame) {
            x = buttonWindow.frame.midX - width / 2
        }
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)

        let y = visible.maxY - 6 - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
    }

    /// Called by SwiftUI whenever the measured content height changes.
    /// Keeps the top edge anchored so the panel grows downward.
    private func setContentHeight(_ height: CGFloat) {
        let clamped = max(height, 100)
        guard abs(clamped - desiredHeight) > 0.5 else { return }
        desiredHeight = clamped

        guard panel.isVisible else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = clamped
        frame.origin.y = top - clamped

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25 * Theme.animationScale
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }

            let flags = KeyCombo.normalized(event.modifierFlags)

            // Recording a new shortcut swallows everything until it gets a valid combo.
            if self.panelState.recordingShortcut {
                if event.keyCode == 53 {
                    self.panelState.recordingShortcut = false
                    return nil
                }
                // Shift alone just types a capital letter — insist on a real modifier
                // so the recorded shortcut can't shadow ordinary typing.
                let hasRealModifier = flags.contains(.command)
                    || flags.contains(.control)
                    || flags.contains(.option)
                guard hasRealModifier else { return nil }
                self.settings.copyShortcut = KeyCombo(
                    keyCode: event.keyCode,
                    modifiers: flags.rawValue,
                    display: KeyCombo.describe(
                        keyCode: event.keyCode,
                        characters: event.charactersIgnoringModifiers,
                        flags: flags
                    )
                )
                self.panelState.recordingShortcut = false
                return nil
            }

            // Esc: back out of settings first, then close the panel.
            if event.keyCode == 53 {
                if self.panelState.showSettings {
                    withAnimation(.snappy(duration: 0.25)) { self.panelState.showSettings = false }
                } else {
                    self.hide()
                }
                return nil
            }

            // ⌘, opens settings.
            if flags == .command, event.charactersIgnoringModifiers == "," {
                withAnimation(.snappy(duration: 0.25)) { self.panelState.showSettings = true }
                return nil
            }

            // Let text fields in settings behave normally.
            guard !self.panelState.showSettings else { return event }

            // The user-configurable copy shortcut.
            if self.settings.copyShortcut.matches(event) {
                self.engine.copyOutput()
                return nil
            }

            // Return (36) or numeric-keypad Enter (76): translate.
            // ⇧Return and ⌘Return both insert a newline.
            if event.keyCode == 36 || event.keyCode == 76 {
                if flags.contains(.shift) { return event }
                if flags.contains(.command) {
                    // AppKit won't treat ⌘Return as a newline on its own; ask the focused
                    // text view directly so the cursor and undo stack stay intact.
                    (self.panel.firstResponder as? NSTextView)?.insertNewline(nil)
                    return nil
                }
                self.engine.translate()
                return nil
            }
            return event
        }
    }

    private func installResignObserver() {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panelState.pinned else { return }
                // If the click landed on the status item, let its action handle the toggle.
                if let button = self.statusItem?.button, let window = button.window,
                   window.frame.contains(NSEvent.mouseLocation) {
                    return
                }
                self.hide()
            }
        }
    }
}
