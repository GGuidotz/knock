// Le scelte di chi usa l'app, salvate in UserDefaults. Predefiniti sensati: si usa senza toccare nulla.

import Foundation

@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    /// In ascolto oppure in pausa (dal menu).
    @Published var listening: Bool { didSet { defaults.set(listening, forKey: "listening") } }
    /// 0…1: quanto deve essere netto un colpo per contare.
    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: "sensitivity") } }
    /// Usa anche accelerometro e giroscopio del Mac (se ci sono).
    @Published var useMotion: Bool { didSet { defaults.set(useMotion, forKey: "useMotion") } }
    /// Ignora i tap mentre scrivi o usi il trackpad.
    @Published var ignoreWhileTyping: Bool { didSet { defaults.set(ignoreWhileTyping, forKey: "ignoreWhileTyping") } }
    /// La voce nella barra lampeggia con la zona riconosciuta.
    @Published var flashMenuBar: Bool { didSet { defaults.set(flashMenuBar, forKey: "flashMenuBar") } }
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    @Published var language: AppLanguage {
        didSet { Localization.language = language; save(language, "language") }
    }
    @Published var autoCheckUpdates: Bool { didSet { defaults.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }

    init() {
        let d = UserDefaults.standard
        listening = d.object(forKey: "listening") as? Bool ?? true
        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 0.5
        useMotion = d.object(forKey: "useMotion") as? Bool ?? true
        ignoreWhileTyping = d.object(forKey: "ignoreWhileTyping") as? Bool ?? true
        flashMenuBar = d.object(forKey: "flashMenuBar") as? Bool ?? true
        onboardingDone = d.bool(forKey: "onboardingDone")
        if let data = d.data(forKey: "language"), let lang = try? JSONDecoder().decode(AppLanguage.self, from: data) {
            language = lang
        } else {
            language = .system
        }
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true
        Localization.language = language
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
