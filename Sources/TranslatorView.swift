import SwiftUI
import Translation

struct TranslatorView: View {
    @ObservedObject var model: TranslatorModel
    var onReplace: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            if !model.axTrusted { accessibilityBanner }
            sourceBox
            resultBox
            footer
        }
        .padding(14)
        .translationTask(model.config) { session in
            await model.perform(with: session)
        }
        .task { await model.loadLanguagesIfNeeded() }
    }

    // MARK: Üst çubuk

    private var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { model.sourceLang },
                                          set: { model.userSelectedSource($0) })) {
                Text(autoLabel).tag("auto")
                Divider()
                ForEach(model.languages) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button {
                model.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .help("Dilleri değiştir")

            Picker("", selection: Binding(get: { model.targetLang },
                                          set: { model.userSelectedTarget($0) })) {
                ForEach(model.languages) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Toggle(isOn: $model.pinned) {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Sabitle (başka yere tıklayınca kapanmasın)")

            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Ayarlar")
        }
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Seçili metni otomatik almak için Erişilebilirlik izni gerekli.")
                .font(.caption)
            Spacer(minLength: 4)
            Button("İzin ver…") { SelectionGrabber.requestTrust() }
                .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            model.axTrusted = SelectionGrabber.isTrusted
        }
    }

    private var autoLabel: String {
        if let d = model.detectedLang, model.sourceLang == "auto" {
            return "Algıla (\(Languages.name(d)))"
        }
        return "Dili algıla"
    }

    // MARK: Kaynak

    private var sourceBox: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(get: { model.sourceText },
                                     set: { model.userEditedSource($0) }))
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(6)
            if model.sourceText.isEmpty {
                Text("Çevrilecek metni yazın veya yapıştırın…")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        .frame(minHeight: 90)
    }

    // MARK: Sonuç

    private var resultBox: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                Group {
                    if model.resultText.isEmpty {
                        Text(model.isWorking ? "Çevriliyor…" : "Çeviri")
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(model.resultText)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
            }
            if model.isWorking {
                ProgressView().controlSize(.small).padding(8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        .frame(minHeight: 110)
    }

    // MARK: Alt çubuk

    private var footer: some View {
        HStack(spacing: 8) {
            if let err = model.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let st = model.status {
                Label(st, systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Label(model.engineLabel, systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(model.copied ? "Kopyalandı ✓" : "Kopyala") { model.copyResult() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.resultText.isEmpty)
                .help("⌘↩")
            Button("Değiştir") { onReplace() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(model.resultText.isEmpty || model.sourceApp == nil)
                .help("Seçili metni çeviriyle değiştir (⇧⌘↩)")
        }
        .font(.caption)
        .controlSize(.small)
    }
}
