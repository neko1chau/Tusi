import Foundation
import Combine

/// Transient UI state shared between the panel controller and SwiftUI views.
@MainActor
final class PanelState: ObservableObject {
    @Published var pinned = false
    @Published var showSettings = false
    /// Shortcuts is a secondary page nested inside Settings — only meaningful while
    /// `showSettings` is also true. Kept in PanelState (not SettingsView's own @State) so
    /// navigating into it and back doesn't reset the rest of Settings.
    @Published var showShortcuts = false
    /// Which profile tab Settings has open. Lives here rather than as SettingsView's own
    /// @State because a trip to the Shortcuts page unmounts and remounts SettingsView —
    /// a local @State would silently reset back to the first tab on return.
    @Published var settingsProfileIndex = 0
    /// When non-nil, the key monitor swallows the next keystroke and binds it to this action.
    @Published var recordingShortcut: ShortcutAction?
    /// Why the last recording attempt was rejected (conflict / missing modifier), shown in Settings.
    @Published var shortcutError: String?
    /// Set when the ⌥Space global hotkey couldn't be registered (usually another app owns
    /// it). Surfaced in Settings so the failure isn't silent — the menu-bar icon still works.
    @Published var globalHotkeyFailed = false
}

extension Notification.Name {
    static let tusiFocusInput = Notification.Name("tusi.focusInput")
}
