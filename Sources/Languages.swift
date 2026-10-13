import Foundation
import NaturalLanguage
import Translation

struct LangItem: Identifiable, Hashable {
    let id: String     // örn. "tr", "en", "zh-Hans"
    let name: String   // yerelleştirilmiş ad
}

enum Languages {

    static func base(_ id: String) -> String {
        Locale.Language(identifier: id).languageCode?.identifier ?? id
    }

    static func name(_ id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }

    static func englishName(_ id: String) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: id) ?? id
    }

    /// Apple Translation'ın desteklediği diller.
    static func load() async -> [LangItem] {
        let langs = await LanguageAvailability().supportedLanguages
        var seen = Set<String>()
        var items: [LangItem] = []
        for lang in langs {
            let id = lang.minimalIdentifier
            if seen.insert(id).inserted {
                items.append(LangItem(id: id, name: name(id)))
            }
        }
        return items.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Cihaz üzerinde dil algılama (NaturalLanguage).
    static func detect(_ text: String, among items: [LangItem]) -> String? {
        let recognizer = NLLanguageRecognizer()
        let s = AppSettings.shared
        // Kısa metinlerde ana/ikinci dile hafif öncelik ver
        var hints: [NLLanguage: Double] = [:]
        hints[NLLanguage(rawValue: base(s.primaryTarget))] = 0.35
        hints[NLLanguage(rawValue: base(s.secondaryTarget))] = 0.35
        recognizer.languageHints = hints
        recognizer.processString(text)
        guard let raw = recognizer.dominantLanguage?.rawValue else { return nil }
        if items.contains(where: { $0.id == raw }) { return raw }
        if let match = items.first(where: { base($0.id) == base(raw) }) { return match.id }
        return raw
    }

    /// Kaynak dile göre otomatik hedef: ana dildeyse ikinci dile, değilse ana dile.
    static func autoTarget(for source: String) -> String {
        let s = AppSettings.shared
        return base(source) == base(s.primaryTarget) ? s.secondaryTarget : s.primaryTarget
    }
}
