// Da un gruppo di tap alla zona del tavolo. Non c'è triangolazione (il microfono arriva a macOS come un canale solo):
// ogni punto del tavolo ha una "firma" di suono e di movimento, e la calibrazione ne raccoglie esempi per zona.
// Classificatore: caratteristiche standardizzate, k vicini più prossimi (k = 5), voto pesato. Se il gruppo è lontano da
// tutti gli esempi (oltre la soglia di rifiuto) la zona resta sconosciuta e non scatta nulla.
// Prova di fattibilità sul MacBook Air M2: 96% sulle 4 zone, 100% alto/basso (dal README, sezione Come funziona).

import Foundation

struct CalibrationSample: Codable {
    let zone: Zone
    let features: [Double]
}

struct ZoneClassifier: Codable {
    private(set) var samples: [CalibrationSample]
    private var mean: [Double]
    private var scale: [Double]
    /// Distanza oltre la quale un gruppo non somiglia abbastanza a nessun esempio.
    private var rejectDistance: Double
    /// Accuratezza stimata lasciando fuori un esempio alla volta (0…1).
    private(set) var accuracy: Double
    let createdAt: Date
    let usesMotion: Bool

    static let k = 5

    /// Allena il classificatore. Servono almeno 3 esempi per zona.
    init?(samples: [CalibrationSample], usesMotion: Bool) {
        let perZone = Dictionary(grouping: samples, by: \.zone)
        guard Zone.allCases.allSatisfy({ (perZone[$0]?.count ?? 0) >= 3 }) else { return nil }
        let dim = samples[0].features.count
        guard dim > 0, samples.allSatisfy({ $0.features.count == dim }) else { return nil }
        self.samples = samples
        self.usesMotion = usesMotion
        createdAt = Date()
        let n = Double(samples.count)
        var m = [Double](repeating: 0, count: dim), s = [Double](repeating: 0, count: dim)
        for x in samples { for i in 0..<dim { m[i] += x.features[i] / n } }
        for x in samples { for i in 0..<dim { s[i] += pow(x.features[i] - m[i], 2) / n } }
        mean = m
        scale = s.map { $0 > 1e-12 ? $0.squareRoot() : 1 }
        // Se le caratteristiche di movimento sono tutte zero (sensore assente), non pesano: la loro scala resta 1.
        rejectDistance = .infinity
        accuracy = 0

        // Lascia fuori un esempio alla volta: accuratezza e distanze tipiche dal vicino più prossimo.
        let z = samples.map { standardize($0.features) }
        var right = 0
        var nearest: [Double] = []
        for i in z.indices {
            var d: [(Double, Zone)] = []
            for j in z.indices where j != i { d.append((Self.distance(z[i], z[j]), samples[j].zone)) }
            d.sort { $0.0 < $1.0 }
            nearest.append(d[0].0)
            if Self.vote(d.prefix(Self.k)).zone == samples[i].zone { right += 1 }
        }
        accuracy = Double(right) / n
        nearest.sort()
        let p95 = nearest[min(nearest.count - 1, Int(Double(nearest.count) * 0.95))]
        rejectDistance = p95 * 1.6
    }

    /// La zona del gruppo e quanto è sicura (0…1), oppure zona nil se non somiglia a nulla.
    func classify(_ features: [Double]) -> (zone: Zone?, confidence: Double) {
        guard features.count == mean.count else { return (nil, 0) }
        let q = standardize(features)
        var d = samples.map { (Self.distance(q, standardize($0.features)), $0.zone) }
        d.sort { $0.0 < $1.0 }
        guard let first = d.first, first.0 <= rejectDistance else { return (nil, 0) }
        let v = Self.vote(d.prefix(Self.k))
        return (v.zone, v.share)
    }

    private func standardize(_ x: [Double]) -> [Double] {
        zip(zip(x, mean), scale).map { ($0.0 - $0.1) / $1 }
    }

    private static func distance(_ a: [Double], _ b: [Double]) -> Double {
        var s = 0.0
        for i in a.indices { let d = a[i] - b[i]; s += d * d }
        return s.squareRoot()
    }

    /// Voto pesato dei vicini (peso 1/distanza): zona vincente e la sua quota.
    private static func vote(_ neighbors: ArraySlice<(Double, Zone)>) -> (zone: Zone, share: Double) {
        var w: [Zone: Double] = [:]
        for (d, z) in neighbors { w[z, default: 0] += 1 / (d + 1e-6) }
        let total = w.values.reduce(0, +)
        let best = w.max { $0.value < $1.value }!
        return (best.key, best.value / max(total, 1e-12))
    }
}

/// La calibrazione salvata: una per Mac, in ~/Library/Application Support/Knock/calibration.json.
enum CalibrationStore {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Knock", isDirectory: true).appendingPathComponent("calibration.json")
    }

    static func load() -> ZoneClassifier? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ZoneClassifier.self, from: data)
    }

    static func save(_ c: ZoneClassifier) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(c).write(to: url, options: .atomic)
    }

    static func delete() { try? FileManager.default.removeItem(at: url) }
}
