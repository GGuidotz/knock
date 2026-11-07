// Cosa fa un interruttore: le azioni e i profili. Un profilo vale per un'app (quando è in primo piano) oppure
// "Sempre"; per ogni interruttore vince l'azione del profilo dell'app davanti, altrimenti quella di "Sempre".
// Solo dati (Codable): chi esegue è ActionRunner (Sources/App).

import Foundation

/// Un tasto con i suoi modificatori, come lo manda la tastiera (codice virtuale di macOS).
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    /// Bit di NSEvent.ModifierFlags (comando, opzione, controllo, maiuscole).
    var modifiers: UInt
    /// Come si legge: "⏎", "⎋", "→", "⌘⇧4".
    var label: String

    static let enter = KeyCombo(keyCode: 36, modifiers: 0, label: "⏎")
    static let escape = KeyCombo(keyCode: 53, modifiers: 0, label: "⎋")
    static let right = KeyCombo(keyCode: 124, modifiers: 0, label: "→")
    static let left = KeyCombo(keyCode: 123, modifiers: 0, label: "←")
}

enum TapAction: Codable, Hashable {
    case none
    case openApp(bundleID: String, name: String)
    case key(KeyCombo)
    case shortcut(name: String)
    case openURL(String)
    /// Muto al microfono di sistema (vale per tutte le app); di nuovo = lo toglie.
    case toggleSystemMute
    /// Knock smette di usare il microfono e ascolta con i soli sensori; di nuovo = lo riaccende.
    case toggleKnockMic
    /// Knock spegne microfono e sensori (risparmio batteria). Si riaccende solo dal menu.
    case stopListening

    var title: String {
        switch self {
        case .none: L("Nessuna azione")
        case .openApp(_, let name): L("Apri %@", name)
        case .key(let k): L("Premi %@", k.label)
        case .shortcut(let name): L("Comando Rapido: %@", name)
        case .openURL(let url): L("Apri %@", url)
        case .toggleSystemMute: L("Muto al microfono di sistema")
        case .toggleKnockMic: L("Spegni o riaccendi il microfono di Knock")
        case .stopListening: L("Spegni tutti i sensori")
        }
    }

    var kind: Kind {
        switch self {
        case .none: .none
        case .openApp: .openApp
        case .key: .key
        case .shortcut: .shortcut
        case .openURL: .openURL
        case .toggleSystemMute: .toggleSystemMute
        case .toggleKnockMic: .toggleKnockMic
        case .stopListening: .stopListening
        }
    }

    /// Le azioni che mandano tasti hanno bisogno del permesso Accessibilità.
    var needsAccessibility: Bool { if case .key = self { return true }; return false }

    enum Kind: String, CaseIterable, Identifiable {
        case none, key, openApp, shortcut, openURL, toggleSystemMute, toggleKnockMic, stopListening
        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: L("Nessuna azione")
            case .key: L("Premi un tasto")
            case .openApp: L("Apri un'app")
            case .shortcut: L("Esegui un Comando Rapido")
            case .openURL: L("Apri un indirizzo")
            case .toggleSystemMute: L("Muto al microfono di sistema")
            case .toggleKnockMic: L("Spegni o riaccendi il microfono di Knock")
            case .stopListening: L("Spegni tutti i sensori")
            }
        }

        var symbol: String {
            switch self {
            case .none: "circle.dashed"
            case .key: "keyboard"
            case .openApp: "app"
            case .shortcut: "square.stack.3d.up"
            case .openURL: "link"
            case .toggleSystemMute: "mic.slash"
            case .toggleKnockMic: "mic.badge.xmark"
            case .stopListening: "power"
            }
        }
    }
}

struct ActionProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    /// nil = "Sempre".
    var bundleIDs: [String]?
    var name: String
    var actions: [String: TapAction] = [:]   // chiave: TapSwitch.id

    var isGlobal: Bool { bundleIDs == nil }

    func action(for s: TapSwitch) -> TapAction { actions[s.id] ?? .none }
    mutating func set(_ a: TapAction, for s: TapSwitch) { actions[s.id] = a }
}

enum ActionProfiles {
    /// I profili pronti al primo avvio (dalla lista di partenza): modificabili e cancellabili.
    static var defaults: [ActionProfile] {
        func sw(_ z: Zone, _ c: TapCount) -> String { TapSwitch(zone: z, count: c).id }
        let approve: [String: TapAction] = [
            sw(.topRight, .double): .key(.enter), sw(.bottomRight, .double): .key(.enter),
            sw(.topLeft, .double): .key(.escape), sw(.bottomLeft, .double): .key(.escape),
        ]
        let slides: [String: TapAction] = [
            sw(.topRight, .double): .key(.right), sw(.bottomRight, .double): .key(.right),
            sw(.topLeft, .double): .key(.left), sw(.bottomLeft, .double): .key(.left),
        ]
        return [
            ActionProfile(bundleIDs: nil, name: L("Sempre"), actions: [
                sw(.topLeft, .triple): .stopListening,
                sw(.bottomRight, .triple): .toggleSystemMute,
                sw(.bottomLeft, .triple): .toggleKnockMic,
            ]),
            ActionProfile(bundleIDs: ["com.anthropic.claudefordesktop"], name: "Claude", actions: approve),
            ActionProfile(bundleIDs: ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"],
                          name: L("Terminale"), actions: approve),
            ActionProfile(bundleIDs: ["com.apple.iWork.Keynote"], name: "Keynote", actions: slides),
            ActionProfile(bundleIDs: ["com.microsoft.Powerpoint"], name: "PowerPoint", actions: slides),
        ]
    }

    /// L'azione per l'interruttore, con l'app `frontmost` davanti.
    static func resolve(_ s: TapSwitch, frontmost: String?, in profiles: [ActionProfile]) -> (TapAction, ActionProfile?) {
        if let frontmost, let p = profiles.first(where: { $0.bundleIDs?.contains(frontmost) == true }) {
            let a = p.action(for: s)
            if a != .none { return (a, p) }
        }
        if let g = profiles.first(where: \.isGlobal) { return (g.action(for: s), g) }
        return (.none, nil)
    }
}
