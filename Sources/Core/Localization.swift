// Lingue di Knock: italiano e inglese. La chiave di ogni testo è la frase italiana: `L("Memoria")`,
// `L("%@ usa il %d%% della CPU", nome, 180)`. Le traduzioni stanno in Localization/en.lproj/Localizable.strings
// (it.lproj è vuoto: la chiave è già il testo). Sistema segue macOS; le altre scelte cambiano subito l'interfaccia.
// Stesso schema di Nod. Solo Foundation: serve anche alla pagina dell'isola.

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system, it, en
    var id: String { rawValue }

    /// Il nome di ogni lingua scritto in quella lingua; "Sistema" tradotto.
    var title: String {
        switch self {
        case .system: L("Sistema")
        case .it: "Italiano"
        case .en: "English"
        }
    }
}

enum Localization {
    /// Aggiornato dalle preferenze quando cambi lingua.
    nonisolated(unsafe) static var language: AppLanguage = .system {
        didSet { bundle = resolveBundle() }
    }
    nonisolated(unsafe) private(set) static var bundle: Bundle = resolveBundle()

    /// Il codice della lingua che si vede adesso (per numeri e date).
    static var effectiveCode: String {
        if language != .system { return language.rawValue }
        return Bundle.main.preferredLocalizations.first ?? "en"
    }

    static var locale: Locale { Locale(identifier: effectiveCode) }

    private static func resolveBundle() -> Bundle {
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let b = Bundle(path: path) else { return .main }
        return b
    }
}

/// Il testo tradotto per la chiave italiana `key`.
func L(_ key: String) -> String {
    Localization.bundle.localizedString(forKey: key, value: key, table: nil)
}

/// Il testo tradotto con valori: `L("Batteria al %d%%", 9)`, `L("%@ liberi", "12 GB")`.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Localization.locale, arguments: args)
}
