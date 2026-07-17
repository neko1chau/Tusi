import Foundation
import Combine

/// Transient UI state shared between the panel controller and SwiftUI views.
@MainActor
final class PanelState: ObservableObject {
    @Published var pinned = false
    @Published var showSettings = false
    /// While true the key monitor swallows the next keystroke and turns it into a shortcut.
    @Published var recordingShortcut = false
}

extension Notification.Name {
    static let tusiFocusInput = Notification.Name("tusi.focusInput")
}
