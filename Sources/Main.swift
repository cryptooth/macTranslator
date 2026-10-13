import AppKit

@main
enum TranslatorMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)   // Dock'ta görünmez, sadece menü çubuğu
            withExtendedLifetime(delegate) {
                app.run()
            }
        }
    }
}
