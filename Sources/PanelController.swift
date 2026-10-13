import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Menü çubuğu simgesi + altında açılan popover (ayrı pencere yok).
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    let model = TranslatorModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!

    var isShown: Bool { popover.isShown }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Çevirmen")
                ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Çevirmen")
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let root = RootView(model: model, onReplace: { [weak self] in self?.replaceSelection() })
        let host = NSHostingController(rootView: root)
        popover.contentViewController = host
        popover.contentSize = NSSize(width: RootView.size.width, height: RootView.size.height)
        popover.behavior = .transient          // dışarı tıklayınca kapanır
        popover.animates = true
        popover.delegate = self
    }

    // MARK: Gösterme / kapatma

    func show(text: String, sourceApp: NSRunningApplication?) {
        if let app = sourceApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            model.sourceApp = app
        }
        model.showSettings = false
        model.load(text: text)
        present()
    }

    func present() {
        guard let button = statusItem.button else { return }
        model.axTrusted = SelectionGrabber.isTrusted
        NSApp.activate()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.close()   // delegate'e sormadan kapatır
    }

    @objc func openSettings() {
        model.showSettings = true
        present()
    }

    /// Çeviriyi panoya koyup kaynak uygulamaya ⌘V gönderir.
    func replaceSelection() {
        let text = model.resultText
        guard !text.isEmpty, let app = model.sourceApp else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        close()
        _ = app.activate(options: [])
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            SelectionGrabber.postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        }
    }

    // MARK: Simge tıklaması

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if popover.isShown {
            close()
        } else {
            model.showSettings = false
            // Önceki uygulamayı "Değiştir" için hatırla
            let front = NSWorkspace.shared.frontmostApplication
            if let app = front, app.bundleIdentifier != Bundle.main.bundleIdentifier {
                model.sourceApp = app
            }
            present()
        }
    }

    /// Sağ tık: kısa menü
    private func showContextMenu() {
        let menu = NSMenu()
        let s = AppSettings.shared
        let hk = NSMenuItem(title: "Kısayol (\(s.hotKeyDisplay))", action: #selector(toggleHotKey), keyEquivalent: "")
        hk.target = self
        hk.state = s.hotKeyEnabled ? .on : .off
        menu.addItem(hk)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Ayarlar…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleHotKey() {
        AppSettings.shared.hotKeyEnabled.toggle()
        HotKeyManager.shared.registerFromSettings()
    }

    // Sabitliyse ya da çeviri (dil paketi onayı) sürüyorsa dışarı tıklamada kapanma
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        !(model.pinned || model.isWorking)
    }
}

/// Popover içeriği: çeviri ↔ ayarlar
struct RootView: View {
    static let size = CGSize(width: 460, height: 440)

    @ObservedObject var model: TranslatorModel
    var onReplace: () -> Void

    var body: some View {
        Group {
            if model.showSettings {
                SettingsView(onBack: { model.showSettings = false })
            } else {
                TranslatorView(model: model, onReplace: onReplace)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}
