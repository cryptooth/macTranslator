import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var languages: [LangItem] = []
    @State private var trusted = false
    @State private var launchAtLogin = false
    @State private var intelligenceAvailable = false
    var onBack: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Çeviri", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Ayarlar").font(.headline)
                Spacer()
                Button("Çıkış") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            form
        }
    }

    private var form: some View {
        Form {
            Section("Kısayol") {
                Toggle("Klavye kısayolu", isOn: Binding(
                    get: { settings.hotKeyEnabled },
                    set: { newValue in
                        settings.hotKeyEnabled = newValue
                        HotKeyManager.shared.registerFromSettings()
                    }))
                LabeledContent("Seçili metni çevir") {
                    HotKeyRecorder(settings: settings)
                }
                .disabled(!settings.hotKeyEnabled)
                Toggle("⌘C ⌘C (iki kez kopyala) ile de çevir", isOn: $settings.doubleCopy)
            }

            Section("Diller") {
                Picker("Ana hedef dil", selection: $settings.primaryTarget) {
                    ForEach(languages) { Text($0.name).tag($0.id) }
                }
                Picker("Metin zaten bu dildeyse", selection: $settings.secondaryTarget) {
                    ForEach(languages) { Text($0.name).tag($0.id) }
                }
                Button("Çeviri dil paketlerini yönet…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section("Çeviri motoru") {
                Picker("Motor", selection: $settings.engine) {
                    Text("Apple Çeviri (Translation, cihaz üzerinde)").tag("apple")
                    Text("Apple Intelligence (cihaz üzerindeki LLM)").tag("intelligence")
                }
                .pickerStyle(.radioGroup)
                if settings.engine == "intelligence" && !intelligenceAvailable {
                    Text("Apple Intelligence bu Mac'te kullanılamıyor ya da kapalı; Apple Çeviri kullanılacak.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Sistem") {
                HStack {
                    Label(trusted ? "Erişilebilirlik izni verildi" : "Erişilebilirlik izni gerekli",
                          systemImage: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Spacer()
                    if !trusted {
                        Button("İzin ver…") { SelectionGrabber.requestTrust() }
                    }
                }
                Toggle("Girişte başlat", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("Translator: login item hatası \(error)")
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
            }
        }
        .formStyle(.grouped)
        .task {
            languages = await Languages.load()
        }
        .onAppear {
            trusted = SelectionGrabber.isTrusted
            launchAtLogin = SMAppService.mainApp.status == .enabled
            intelligenceAvailable = IntelligenceTranslator.isAvailable
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = SelectionGrabber.isTrusted
        }
    }
}

/// Tıkla → yeni tuş kombinasyonuna bas.
struct HotKeyRecorder: View {
    @ObservedObject var settings: AppSettings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Tuşlara basın… (Esc: iptal)" : settings.hotKeyDisplay) {
            recording ? stop() : start()
        }
        .frame(minWidth: 120)
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == UInt16(kVK_Escape) {
                    stop()
                    return
                }
                let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                guard !mods.isEmpty, mods != .shift else {
                    NSSound.beep()   // en az bir ⌘/⌥/⌃ gerekli
                    return
                }
                settings.hotKeyCode = UInt32(event.keyCode)
                settings.hotKeyModifiers = AppSettings.carbonModifiers(from: mods)
                settings.hotKeyChar = AppSettings.keyName(for: event)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
        HotKeyManager.shared.registerFromSettings()
    }
}
