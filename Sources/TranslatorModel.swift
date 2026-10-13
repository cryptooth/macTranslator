import AppKit
import SwiftUI
import Translation

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var sourceText = ""
    @Published var resultText = ""
    @Published var sourceLang = "auto"          // "auto" ya da dil kimliği
    @Published var targetLang = AppSettings.shared.primaryTarget
    @Published var detectedLang: String?
    @Published var languages: [LangItem] = []
    @Published var isWorking = false
    @Published var status: String?
    @Published var errorMessage: String?
    @Published var pinned = false
    @Published var copied = false
    @Published var showSettings = false
    @Published var axTrusted = SelectionGrabber.isTrusted
    /// SwiftUI .translationTask bu değere bağlı; değişince çeviri tetiklenir.
    @Published var config: TranslationSession.Configuration?

    var sourceApp: NSRunningApplication?
    private var targetManuallySet = false
    private var pendingTask: Task<Void, Never>?
    private var pendingText = ""

    var usesIntelligence: Bool {
        AppSettings.shared.engine == "intelligence" && IntelligenceTranslator.isAvailable
    }

    var engineLabel: String {
        usesIntelligence ? "Apple Intelligence · cihaz üzerinde" : "Apple Çeviri · cihaz üzerinde"
    }

    // MARK: Girdi

    func load(text: String) {
        sourceText = text
        resultText = ""
        errorMessage = nil
        status = nil
        sourceLang = "auto"
        targetManuallySet = false
        requestTranslate(delay: 0)
    }

    func userEditedSource(_ text: String) {
        sourceText = text
        requestTranslate(delay: 0.45)
    }

    func userSelectedSource(_ id: String) {
        sourceLang = id
        requestTranslate(delay: 0)
    }

    func userSelectedTarget(_ id: String) {
        targetLang = id
        targetManuallySet = true
        requestTranslate(delay: 0)
    }

    func swapLanguages() {
        let currentSource = sourceLang == "auto" ? (detectedLang ?? targetLang) : sourceLang
        let newText = resultText.isEmpty ? sourceText : resultText
        sourceLang = targetLang
        targetLang = currentSource
        targetManuallySet = true
        sourceText = newText
        resultText = ""
        requestTranslate(delay: 0)
    }

    func copyResult() {
        guard !resultText.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(resultText, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }

    func loadLanguagesIfNeeded() async {
        if languages.isEmpty { languages = await Languages.load() }
    }

    // MARK: Çeviri akışı

    func requestTranslate(delay: Double) {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.startTranslation()
        }
    }

    private func startTranslation() async {
        errorMessage = nil
        status = nil
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resultText = ""
            detectedLang = nil
            return
        }
        await loadLanguagesIfNeeded()
        if Task.isCancelled { return }

        let src: String
        if sourceLang == "auto" {
            guard let detected = Languages.detect(trimmed, among: languages) else {
                errorMessage = "Dil algılanamadı — kaynak dili seçin."
                return
            }
            detectedLang = detected
            src = detected
        } else {
            src = sourceLang
        }
        if !targetManuallySet { targetLang = Languages.autoTarget(for: src) }
        let tgt = targetLang

        if Languages.base(src) == Languages.base(tgt) {
            resultText = sourceText
            status = "Kaynak ve hedef aynı dil"
            return
        }

        if usesIntelligence {
            let text = sourceText
            pendingText = text
            isWorking = true
            do {
                let out = try await IntelligenceTranslator.translate(text, to: tgt)
                if text == pendingText { resultText = out }
            } catch {
                if text == pendingText, !(error is CancellationError) {
                    errorMessage = "Apple Intelligence: \(error.localizedDescription)"
                }
            }
            isWorking = false
            return
        }

        let s = Locale.Language(identifier: src)
        let t = Locale.Language(identifier: tgt)
        let availability = await LanguageAvailability().status(from: s, to: t)
        if Task.isCancelled { return }
        switch availability {
        case .unsupported:
            errorMessage = "\(Languages.name(src)) → \(Languages.name(tgt)) desteklenmiyor."
            return
        case .supported:
            status = "Dil paketi ilk kullanımda indirilecek (sonra tamamen çevrimdışı)"
        case .installed:
            break
        @unknown default:
            break
        }

        pendingText = sourceText
        if var current = config, current.source == s, current.target == t {
            current.invalidate()          // aynı dil çifti: yeniden çalıştır
            config = current
        } else {
            config = TranslationSession.Configuration(source: s, target: t)
        }
    }

    /// .translationTask tarafından çağrılır.
    func perform(with session: TranslationSession) async {
        let text = pendingText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await session.translate(text)
            if text == pendingText {
                resultText = response.targetText
                status = nil
            }
        } catch {
            if text == pendingText, !(error is CancellationError) {
                errorMessage = "Çeviri hatası: \(error.localizedDescription)"
            }
        }
    }
}
