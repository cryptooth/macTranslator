import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Başka bir uygulamada seçili metni alır.
/// 1) Erişilebilirlik API'si (pano'ya dokunmaz)
/// 2) Olmazsa ⌘C simülasyonu + panonun eski içeriğini geri yükleme
enum SelectionGrabber {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Sistem istemini dener (macOS bunu yalnızca ilk seferde gösterir) ve
    /// her durumda Sistem Ayarları › Gizlilik › Erişilebilirlik bölümünü açar.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        guard !trusted else { return }
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    static func selectedTextViaAX() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement

        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    @MainActor
    static func selectedTextViaCopy() async -> String? {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount

        postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        for _ in 0..<20 {   // ~500 ms bekle
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pb.changeCount != before {
                let text = pb.string(forType: .string)
                restore(pb, saved)
                return text
            }
        }
        return nil
    }

    static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Pano yedekleme

    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    private static func restore(_ pb: NSPasteboard, _ items: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let newItems: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(newItems)
    }
}
