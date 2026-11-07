// I tipi di Knock: le 4 zone del tavolo, il numero di tap e l'interruttore che ne risulta (4 x 2 = 8).
// Solo Foundation.

import Foundation

enum Zone: String, CaseIterable, Codable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: L("In alto a sinistra")
        case .topRight: L("In alto a destra")
        case .bottomLeft: L("In basso a sinistra")
        case .bottomRight: L("In basso a destra")
        }
    }

    /// Dove toccare, detto in una frase (guida e calibrazione).
    var hint: String {
        switch self {
        case .topLeft: L("A sinistra del Mac, all'altezza della cerniera dello schermo")
        case .topRight: L("A destra del Mac, all'altezza della cerniera dello schermo")
        case .bottomLeft: L("A sinistra del Mac, all'altezza del bordo vicino a te")
        case .bottomRight: L("A destra del Mac, all'altezza del bordo vicino a te")
        }
    }

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

enum TapCount: Int, CaseIterable, Codable, Identifiable {
    case double = 2, triple = 3
    var id: Int { rawValue }
    var title: String { self == .double ? L("Doppio tap") : L("Triplo tap") }
}

/// Uno degli 8 interruttori.
struct TapSwitch: Hashable, Codable, Identifiable {
    let zone: Zone
    let count: TapCount
    var id: String { "\(zone.rawValue).\(count.rawValue)" }
    var title: String { "\(count.title), \(zone.title.lowercased())" }

    static let all: [TapSwitch] = Zone.allCases.flatMap { z in TapCount.allCases.map { TapSwitch(zone: z, count: $0) } }
}

/// Un gruppo di tap ravvicinati appena chiuso dal rilevatore: quanti colpi, quando, e le caratteristiche medie
/// (suono e movimento) che servono a capire la zona.
struct TapPattern {
    let taps: Int
    let date: Date
    let features: [Double]
    /// L'accelerometro ha dato dati per tutti i tap del gruppo.
    let hasMotion: Bool
    /// Livello del primo colpo in dB (per la diagnostica e la sensibilità).
    let level: Double
}

/// Ciò che l'app riceve: un interruttore riconosciuto, oppure un gruppo che non si è riuscito ad attribuire.
struct TapEvent: Identifiable {
    let id = UUID()
    let date: Date
    let taps: Int
    let zone: Zone?
    /// 0…1: quanto il gruppo somiglia agli esempi della calibrazione.
    let confidence: Double
    /// Cosa è successo (azione eseguita o errore), per il registro e il menu.
    var actionTitle: String?

    var tapSwitch: TapSwitch? {
        guard let zone, let count = TapCount(rawValue: taps) else { return nil }
        return TapSwitch(zone: zone, count: count)
    }
}

/// Come ascolta Knock.
enum ListeningMode: String, CaseIterable, Codable, Identifiable {
    /// Microfono + sensori di movimento (predefinita).
    case hybrid
    /// Solo sensori di movimento: niente microfono, niente pallino arancione (sperimentale, MacBook M2 e successivi).
    case motionOnly
    /// Solo microfono (Mac senza sensore o sensore spento).
    case micOnly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hybrid: L("Microfono e sensori")
        case .motionOnly: L("Solo sensori (sperimentale)")
        case .micOnly: L("Solo microfono")
        }
    }

    var usesMic: Bool { self != .motionOnly }
    var usesMotion: Bool { self != .micOnly }
}
