import AppKit
import Carbon.HIToolbox

/// Kalıcı ayarlar (UserDefaults).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Metin bu dilde değilse buna çevrilir.
    @Published var primaryTarget: String { didSet { save(primaryTarget, "primaryTarget") } }
    /// Metin zaten ana dildeyse buna çevrilir.
    @Published var secondaryTarget: String { didSet { save(secondaryTarget, "secondaryTarget") } }
    /// "apple" = Translation framework, "intelligence" = Apple Intelligence (Foundation Models)
    @Published var engine: String { didSet { save(engine, "engine") } }
    /// DeepL gibi ⌘C ⌘C ile tetikleme
    @Published var doubleCopy: Bool { didSet { save(doubleCopy, "doubleCopy") } }
    /// Klavye kısayolu açık/kapalı
    @Published var hotKeyEnabled: Bool { didSet { save(hotKeyEnabled, "hotKeyEnabled") } }

    @Published var hotKeyCode: UInt32 { didSet { save(Int(hotKeyCode), "hotKeyCode") } }
    @Published var hotKeyModifiers: UInt32 { didSet { save(Int(hotKeyModifiers), "hotKeyModifiers") } }
    @Published var hotKeyChar: String { didSet { save(hotKeyChar, "hotKeyChar") } }

    private init() {
        let d = UserDefaults.standard
        primaryTarget = d.string(forKey: "primaryTarget") ?? "tr"
        secondaryTarget = d.string(forKey: "secondaryTarget") ?? "en"
        engine = d.string(forKey: "engine") ?? "apple"
        doubleCopy = d.object(forKey: "doubleCopy") as? Bool ?? false
        hotKeyEnabled = d.object(forKey: "hotKeyEnabled") as? Bool ?? true
        if d.object(forKey: "hotKeyCode") != nil {
            hotKeyCode = UInt32(d.integer(forKey: "hotKeyCode"))
            hotKeyModifiers = UInt32(d.integer(forKey: "hotKeyModifiers"))
            hotKeyChar = d.string(forKey: "hotKeyChar") ?? "?"
        } else {
            // Varsayılan: ⌃⌥T
            hotKeyCode = UInt32(kVK_ANSI_T)
            hotKeyModifiers = UInt32(controlKey | optionKey)
            hotKeyChar = "T"
        }
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    var hotKeyDisplay: String {
        var s = ""
        if hotKeyModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if hotKeyModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if hotKeyModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if hotKeyModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + hotKeyChar
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let c = (event.charactersIgnoringModifiers ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            return c.isEmpty ? "#\(event.keyCode)" : c
        }
    }
}
