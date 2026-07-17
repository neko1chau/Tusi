import SwiftUI

enum Theme {
    /// System accent color — whatever the user picked in System Settings ▸ Appearance.
    /// Using it (instead of a baked-in brand gradient) is what makes controls read as
    /// native macOS chrome rather than a cross-platform app that shipped its own palette.
    static let accent = Color.accentColor
    static let success = Color(nsColor: .systemGreen)

    static let cornerRadius: CGFloat = 20
    static let contentFont = Font.system(size: 15)

    /// TUSI_SLOWMO stretches every panel animation so transitions can be inspected
    /// frame by frame. 1 in normal runs.
    static let animationScale: Double = ProcessInfo.processInfo.environment["TUSI_SLOWMO"] != nil ? 10 : 1
}
