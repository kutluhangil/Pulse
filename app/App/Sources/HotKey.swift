import AppKit
import Carbon.HIToolbox

/// Global ⌃⌥⌘P shortcut that toggles the panel from any app (Carbon hot key:
/// works in the sandbox and needs no Accessibility permission).
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private static var current: HotKey?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var isRegistered: Bool { ref != nil }

    func register() {
        guard ref == nil else { return }
        HotKey.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.current?.action() } }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x504C_5345), id: 1) // "PLSE"
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey | controlKey), id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        ref = nil
        handlerRef = nil
    }
}
