import AppKit
import Carbon.HIToolbox

/// Sistem genelinde kısayol (Carbon RegisterEventHotKey — ek izin gerektirmez).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onTrigger: (() -> Void)?
    private(set) var isRegistered = false
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    private init() {}

    @discardableResult
    func registerFromSettings() -> Bool {
        let s = AppSettings.shared
        guard s.hotKeyEnabled else {
            unregister()
            return false
        }
        return register(keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x54524E53), id: 1) // 'TRNS'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = (status == noErr)
        if !isRegistered { NSLog("Translator: kısayol kaydedilemedi (\(status))") }
        return isRegistered
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        isRegistered = false
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in HotKeyManager.shared.onTrigger?() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}
