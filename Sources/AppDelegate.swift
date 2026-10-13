import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let popover = MenuBarController()
    private var globalKeyMonitor: Any?
    private var lastCopyTime = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        popover.setup()

        HotKeyManager.shared.onTrigger = { [weak self] in self?.translateSelection() }
        HotKeyManager.shared.registerFromSettings()

        startDoubleCopyMonitor()

        if !SelectionGrabber.isTrusted {
            // Yalnızca sistem istemini dene; Ayarlar'ı açılışta zorla açma
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }

    // MARK: Ana iş

    func translateSelection() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier == Bundle.main.bundleIdentifier {
            // Kendi popover'ımız öndeyse kısayol aç/kapa gibi davranır
            if popover.isShown { popover.close() } else { popover.present() }
            return
        }
        if let text = SelectionGrabber.selectedTextViaAX() {
            popover.show(text: text, sourceApp: front)
            return
        }
        guard SelectionGrabber.isTrusted else {
            popover.show(text: "", sourceApp: front)   // içinde izin uyarısı görünür
            return
        }
        Task {
            let text = await SelectionGrabber.selectedTextViaCopy()
            popover.show(text: text ?? "", sourceApp: front)
        }
    }

    // DeepL tarzı ⌘C ⌘C
    private func startDoubleCopyMonitor() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isRepeat = event.isARepeat
            Task { @MainActor in
                self?.handleGlobalKey(code: code, flags: flags, isRepeat: isRepeat)
            }
        }
    }

    private func handleGlobalKey(code: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool) {
        guard AppSettings.shared.doubleCopy, !isRepeat,
              code == UInt16(kVK_ANSI_C), flags == .command else { return }
        let now = Date()
        if now.timeIntervalSince(lastCopyTime) < 0.5 {
            lastCopyTime = .distantPast
            let front = NSWorkspace.shared.frontmostApplication
            Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                popover.show(text: text, sourceApp: front)
            }
        } else {
            lastCopyTime = now
        }
    }

    // LSUIElement uygulamada ⌘C/⌘V/⌘A'nın metin alanlarında çalışması için gizli ana menü
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ayarlar…", action: #selector(MenuBarController.openSettings), keyEquivalent: ",").target = popover
        appMenu.addItem(withTitle: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Düzen")
        edit.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
