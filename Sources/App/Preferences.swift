// Le scelte di chi usa l'app, salvate in UserDefaults. Predefiniti sensati: si usa senza toccare nulla.

import Foundation

@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    /// In ascolto oppure in pausa (dal menu).
    @Published var listening: Bool { didSet { defaults.set(listening, forKey: "listening") } }
    /// 0…1: quanto deve essere netto un colpo per contare.
    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: "sensitivity") } }
    /// Come ascolta: microfono e sensori, solo sensori, solo microfono.
    @Published var mode: ListeningMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    /// Il microfono di Knock è spento dall'azione apposita: si ascolta con i soli sensori.
    @Published var knockMicOff: Bool { didSet { defaults.set(knockMicOff, forKey: "knockMicOff") } }
    /// Suono breve quando un interruttore scatta.
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound") } }
    /// Le azioni: "Sempre" e i profili per app.
    @Published var profiles: [ActionProfile] { didSet { save(profiles, "profiles") } }
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
        // 0.1 aveva "usa anche il sensore di movimento": spento = solo microfono.
        let legacyMotion = d.object(forKey: "useMotion") as? Bool ?? true
        mode = ListeningMode(rawValue: d.string(forKey: "mode") ?? "") ?? (legacyMotion ? .hybrid : .micOnly)
        knockMicOff = d.bool(forKey: "knockMicOff")
        sound = d.bool(forKey: "sound")
        if let data = d.data(forKey: "profiles"), let p = try? JSONDecoder().decode([ActionProfile].self, from: data) {
            profiles = p
        } else {
            profiles = ActionProfiles.defaults
        }
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
