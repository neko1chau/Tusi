import Carbon
import Foundation

/// Registers ⌥Space as a global hotkey via Carbon (no accessibility permission needed).
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    private static let keyCodeSpace: UInt32 = 0x31
    private static let optionModifier: UInt32 = 0x0800

    init?(callback: @escaping () -> Void) {
        self.callback = callback

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var handler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.callback() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard installStatus == noErr else { return nil }
        handlerRef = handler

        let hotKeyID = EventHotKeyID(signature: Self.fourCC("TUSI"), id: 1)
        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            Self.keyCodeSpace,
            Self.optionModifier,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard registerStatus == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
        hotKeyRef = ref
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private static func fourCC(_ string: String) -> FourCharCode {
        string.utf16.reduce(0) { ($0 << 8) + FourCharCode($1) }
    }
}
