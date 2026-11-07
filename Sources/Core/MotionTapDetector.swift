// Il rilevatore con i soli sensori di movimento (niente microfono): un colpo è un salto dell'accelerometro rispetto
// alla linea di base, misurato contro ciò che c'era PRIMA del colpo (da 40 a 10 ms fa), perché un tap sale in qualche
// millisecondo e i campioni appena precedenti fanno già parte del colpo. Colpi a meno di 450 ms formano un gruppo,
// chiuso dopo 600 ms senza colpi; le caratteristiche sono quelle di movimento di TapDetector (le audio restano a zero).
// Prova sul MacBook Air M2: rumore a riposo 0,00075 g (picchi 0,005 g), tap tipici 0,02-0,07 g; gruppi giusti 77%,
// zone 86%. Più debole del microfono sui tap vicino alla cerniera: per questo è "sperimentale".

import Foundation

final class MotionTapDetector {
    /// Soglia minima in g: con sensibilità 0 = 0,012, 1 = 0,005.
    var minThreshold = 0.008
    var onPattern: ((TapPattern) -> Void)?

    private let motion: MotionSensor
    private let queue: DispatchQueue
    private var base = (0.0, 0.0, 0.0)
    private var primed = 0
    private var noiseVar = 1e-6
    private var lastOnset = -1.0
    private var ring = [Double](repeating: 0, count: 32)
    private var ringI = 0
    private var open: [(t: Double, features: [Double])] = []
    private var timer: DispatchSourceTimer?

    init(motion: MotionSensor, queue: DispatchQueue) {
        self.motion = motion
        self.queue = queue
    }

    func start() {
        motion.onAccel = { [weak self] s in self?.feed(s) }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.05, leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        motion.onAccel = nil
        timer?.cancel()
        timer = nil
        queue.async { self.open.removeAll() }
        primed = 0
    }

    /// Chiamato dal thread del sensore per ogni campione dell'accelerometro (circa 800 al secondo): poche operazioni.
    private func feed(_ s: MotionSample) {
        if primed < 400 {   // mezzo secondo per trovare la linea di base
            let a = primed == 0 ? 1.0 : 0.02
            base = (base.0 + a * (s.x - base.0), base.1 + a * (s.y - base.1), base.2 + a * (s.z - base.2))
            primed += 1
            return
        }
        let d = (s.x - base.0, s.y - base.1, s.z - base.2)
        let mag = (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).squareRoot()
        let thr = max(minThreshold, 8 * noiseVar.squareRoot())
        var before = 0.0
        for k in 8..<ring.count { before = max(before, ring[(ringI - 1 - k + 2 * ring.count) % ring.count]) }
        ring[ringI] = mag
        ringI = (ringI + 1) % ring.count
        if mag > thr && mag > 2.5 * before && s.t - lastOnset > 0.12 {
            lastOnset = s.t
            let t = s.t
            // Le caratteristiche usano i 100 ms dopo il colpo: si calcolano quando sono arrivati.
            queue.asyncAfter(deadline: .now() + 0.13) { [weak self] in self?.addTap(at: t) }
            return
        }
        if s.t - lastOnset > 0.3 {
            base = (base.0 + 0.01 * d.0, base.1 + 0.01 * d.1, base.2 + 0.01 * d.2)
            if mag < thr / 2 { noiseVar = 0.995 * noiseVar + 0.005 * mag * mag }
        }
    }

    private func addTap(at t: Double) {
        if let last = open.last, t - last.t > 0.45 { close() }
        let audio = [Double](repeating: 0, count: 4 + TapDetector.bandCount)
        open.append((t, audio + TapDetector.motionFeatures(motion, at: t).values))
    }

    private func tick() {
        if let last = open.last, MotionSensor.now - last.t > 0.6 { close() }
    }

    private func close() {
        guard !open.isEmpty else { return }
        let taps = open
        open.removeAll()
        let n = Double(taps.count)
        var mean = [Double](repeating: 0, count: TapDetector.featureCount)
        for tap in taps { for (i, v) in tap.features.enumerated() where i < mean.count { mean[i] += v / n } }
        let date = Date(timeIntervalSinceNow: taps[0].t - MotionSensor.now)
        onPattern?(TapPattern(taps: taps.count, date: date, features: mean, hasMotion: true, level: 0))
    }
}
