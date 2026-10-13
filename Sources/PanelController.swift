import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Esc ile kapanan panel.
final class TranslatorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
            orderOut(nil)
            return
        }
        super.sendEvent(event)
    }
}

/// Menü çubuğu simgesi + altında açılan, boyutlandırılabilir ve koparılabilir panel.
///  • Bağlı mod: simgenin altında açılır, başka yere tıklayınca kapanır.
///  • Kopuk mod: sürükleyerek (veya ⧉ düğmesiyle) ayrılır, her zaman üstte duran normal pencere olur.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    let model = TranslatorModel()
    private var statusItem: NSStatusItem!
    private var panel: TranslatorPanel!

    private static let sizeKey = "panelSize"
    private static let defaultSize = NSSize(width: 460, height: 440)
    private static let minSize = NSSize(width: 380, height: 320)

    var isShown: Bool { panel?.isVisible ?? false }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Çevirmen")
                ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Çevirmen")
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        panel = makePanel()
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
        model.axTrusted = SelectionGrabber.isTrusted
        if !model.isDetached { positionUnderStatusItem() }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
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
        if !model.isDetached { close() }
        _ = app.activate(options: [])
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            SelectionGrabber.postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        }
    }

    func toggleDetach() {
        setDetached(!model.isDetached)
        if !model.isDetached { positionUnderStatusItem() }
    }

    // MARK: Panel

    private func makePanel() -> TranslatorPanel {
        let p = TranslatorPanel(
            contentRect: NSRect(origin: .zero, size: savedSize()),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.minSize = Self.minSize
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.delegate = self

        let root = RootView(
            model: model,
            onReplace: { [weak self] in self?.replaceSelection() },
            onToggleDetach: { [weak self] in self?.toggleDetach() })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []          // boyutu pencere belirlesin
        p.contentView = host
        panel = p
        applyMode()
        return p
    }

    private func setDetached(_ detached: Bool) {
        guard model.isDetached != detached else { return }
        model.isDetached = detached
        applyMode()
    }

    private func applyMode() {
        // Kopuk modda kapatma düğmesi görünsün
        panel?.standardWindowButton(.closeButton)?.isHidden = !model.isDetached
    }

    private func positionUnderStatusItem() {
        guard let button = statusItem.button, let win = button.window else {
            panel.center()
            return
        }
        let anchor = win.convertToScreen(button.convert(button.bounds, to: nil))
        let vf = (win.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        var x = anchor.midX - size.width / 2
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        var y = anchor.minY - size.height - 6
        y = max(y, vf.minY + 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func savedSize() -> NSSize {
        if let s = UserDefaults.standard.string(forKey: Self.sizeKey) {
            let size = NSSizeFromString(s)
            if size.width >= Self.minSize.width, size.height >= Self.minSize.height { return size }
        }
        return Self.defaultSize
    }

    // MARK: NSWindowDelegate

    /// Yalnızca kullanıcı sürüklediğinde çağrılır → panel koparılır.
    func windowWillMove(_ notification: Notification) {
        if !model.isDetached { setDetached(true) }
    }

    /// Bağlı moddayken başka yere tıklanınca kapan (dil paketi onayı sürerken değil).
    func windowDidResignKey(_ notification: Notification) {
        guard !model.isDetached, !model.isWorking else { return }
        panel.orderOut(nil)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: Self.sizeKey)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.orderOut(nil)
        return false
    }

    // MARK: Simge tıklaması

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if panel.isVisible {
            close()
        } else {
            model.showSettings = false
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
        let detach = NSMenuItem(title: "Ayrı Pencere", action: #selector(menuToggleDetach), keyEquivalent: "")
        detach.target = self
        detach.state = model.isDetached ? .on : .off
        menu.addItem(detach)
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

    @objc private func menuToggleDetach() {
        toggleDetach()
        present()
    }
}

/// Panel içeriği: üst tutamak + çeviri ↔ ayarlar
struct RootView: View {
    @ObservedObject var model: TranslatorModel
    var onReplace: () -> Void
    var onToggleDetach: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Başlık çubuğu alanı: bağlıyken sürükleme tutamağı, kopukken başlık
            ZStack {
                if model.isDetached {
                    Text("Translator")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 5)
                        .help("Ayrı pencere yapmak için sürükleyin")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)

            Group {
                if model.showSettings {
                    SettingsView(onBack: { model.showSettings = false })
                } else {
                    TranslatorView(model: model, onReplace: onReplace, onToggleDetach: onToggleDetach)
                }
            }
        }
        .frame(minWidth: 380, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
    }
}
