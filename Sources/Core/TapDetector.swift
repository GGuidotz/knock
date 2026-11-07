// Il rilevatore: dal segnale del microfono ai gruppi di tap.
//  1. passa-alto a 100 Hz (via il rimbombo e il rumore di fondo basso);
//  2. energia a finestre da 5 ms; un tap è un SALTO di energia: almeno `riseRatio` volte il massimo degli ultimi 50 ms
//     e ben sopra il rumore di fondo. La coda che si spegne dopo un colpo non sale mai, quindi non conta come colpo nuovo
//     (era l'errore della prima prova: un doppio tap diventava 6-12 colpi);
//  3. per ogni colpo, 40 ms di suono -> 24 bande di spettro (forma, non volume), centroide, decadimento, picco;
//     più il movimento del Mac nello stesso istante (picco con segno ed energia su x, y, z di accelerometro e giroscopio);
//  4. colpi a meno di 450 ms l'uno dall'altro formano un gruppo, chiuso dopo 600 ms di silenzio.
// Gira sulla coda del motore (TapEngine), mai sul thread audio. Nessun suono viene salvato.

import Accelerate
import Foundation

final class TapDetector {
    static let bandCount = 24
    static let motionFeatureCount = 12
    static var featureCount: Int { 4 + bandCount + motionFeatureCount }

    /// Più alto = servono colpi più netti (meno falsi allarmi, più tap persi).
    var threshold: Float = 30
    var riseRatio: Float = 8
    var onPattern: ((TapPattern) -> Void)?

    private let sr: Double
    private let hop: Int, winLen: Int, tailLen: Int, refractory: Int
    private let fftSize: Int
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let bandEdges: [Int]
    private let motion: MotionSensor?

    private var buf: [Float] = []
    private var bufStart = 0
    private var absIndex = 0
    private var t0: Double?
    private var xPrev: Float = 0, yPrev: Float = 0
    private let hpA: Float
    private var acc: Float = 0, accN = 0
    private var noise: Float = 1e-8
    private var lastOnset = Int.min / 2
    private var recent = [Float](repeating: 0, count: 10)
    private var recentI = 0
    private var pending: [Int] = []

    private struct Tap { let t: Double; let features: [Double]; let motion: Bool; let level: Double }
    private var open: [Tap] = []

    init(sampleRate: Double, motion: MotionSensor?) {
        sr = sampleRate
        self.motion = motion
        hop = Int(sr * 0.005); winLen = Int(sr * 0.04); tailLen = Int(sr * 0.12); refractory = Int(sr * 0.12)
        let rc = 1.0 / (2 * Double.pi * 100)
        hpA = Float(rc / (rc + 1 / sr))
        var n = 1, log2n = 0
        while n < winLen { n *= 2; log2n += 1 }
        fftSize = n
        fft = vDSP.FFT(log2n: vDSP_Length(log2n), radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: winLen, isHalfWindow: false)
        let rate = sampleRate, fmax = min(20000, sampleRate / 2 - 100), bands = Self.bandCount
        bandEdges = (0...bands).map { i in
            let f = 80 * pow(fmax / 80, Double(i) / Double(bands))
            return min(n / 2 - 1, max(1, Int(f / rate * Double(n))))
        }
    }

    private func time(of index: Int) -> Double { (t0 ?? 0) + Double(index) / sr }

    /// Un blocco di campioni mono; `hostTime` è l'istante del primo campione (0 se non noto).
    func process(_ x: [Float], hostTime: UInt64) {
        if t0 == nil { t0 = hostTime != 0 ? MotionSensor.hostSeconds(hostTime) : MotionSensor.now }
        buf.reserveCapacity(buf.count + x.count)
        for s in x {
            let y = hpA * (yPrev + s - xPrev)
            xPrev = s; yPrev = y
            buf.append(y)
            absIndex += 1
            acc += y * y; accN += 1
            guard accN == hop else { continue }
            let e = acc / Float(hop)
            let onset = absIndex - hop
            let rise = e > riseRatio * (recent.max() ?? 0)
            recent[recentI] = e; recentI = (recentI + 1) % recent.count
            if rise && e > max(noise * threshold, 1e-7) && onset - lastOnset > refractory {
                lastOnset = onset
                pending.append(onset)
            } else if onset - lastOnset > Int(sr * 0.15) && e < noise * 4 {
                noise = 0.99 * noise + 0.01 * e
            }
            acc = 0; accN = 0
        }
        while let p = pending.first, absIndex >= p + tailLen {
            pending.removeFirst()
            extract(onset: p)
        }
        if !open.isEmpty, let last = open.last, time(of: absIndex) - last.t > 0.6 { closeGroup() }
        let keep = Int(sr * 1.5)
        if buf.count > keep * 2 {
            let drop = buf.count - keep
            buf.removeFirst(drop)
            bufStart += drop
        }
    }

    /// Dimentica il gruppo aperto (per esempio quando si mette in pausa).
    func reset() { open.removeAll(); pending.removeAll() }

    // MARK: - Caratteristiche di un colpo

    private func extract(onset: Int) {
        let s0 = max(bufStart, onset - Int(sr * 0.002)) - bufStart
        guard s0 >= 0, s0 + tailLen <= buf.count else { return }
        let w = Array(buf[s0..<(s0 + winLen)])
        let power = spectrum(w)
        let total = Double(power.reduce(0, +)) + 1e-20
        let level = 10 * log10(total)
        let peak = 20 * log10(Double(vDSP.maximumMagnitude(w)) + 1e-12)
        var centroid = 0.0
        for (k, v) in power.enumerated() { centroid += Double(k) * sr / Double(fftSize) * Double(v) }
        centroid /= total
        var bands: [Double] = []
        for i in 0..<Self.bandCount {
            let lo = bandEdges[i], hi = max(bandEdges[i] + 1, bandEdges[i + 1])
            bands.append(10 * log10(Double(power[lo..<hi].reduce(0, +)) + 1e-20))
        }
        let mean = bands.reduce(0, +) / Double(bands.count)
        bands = bands.map { $0 - mean }   // forma dello spettro, indipendente dal volume

        // Decadimento: frame da 2 ms, tempo dal picco a -20 dB.
        let fr = max(1, Int(sr * 0.002))
        var env: [Double] = []
        var i = s0
        while i + fr <= s0 + tailLen {
            env.append(Double(vDSP.sumOfSquares(buf[i..<(i + fr)])) / Double(fr))
            i += fr
        }
        var decay = 0.0
        if let pk = env.indices.max(by: { env[$0] < env[$1] }) {
            let end = env[pk...].firstIndex(where: { $0 < env[pk] / 100 }) ?? env.count
            decay = Double(end - pk) * 2
        }

        let t = time(of: onset)
        let (motionFeatures, hasMotion) = motionFeaturesAt(t)
        let tap = Tap(t: t, features: [level, peak, centroid / 1000, decay] + bands + motionFeatures,
                      motion: hasMotion, level: level)
        if let last = open.last, t - last.t > 0.45 { closeGroup() }
        open.append(tap)
    }

    private func spectrum(_ x: [Float]) -> [Float] {
        var input = [Float](repeating: 0, count: fftSize)
        vDSP.multiply(x, window, result: &input[0..<winLen])
        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half), imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                input.withUnsafeBufferPointer { inp in
                    inp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                var out = split
                fft.forward(input: split, output: &out)
                power.withUnsafeMutableBufferPointer { pp in
                    vDSP_zvmags(&out, 1, pp.baseAddress!, 1, vDSP_Length(half))
                }
            }
        }
        power[0] = 0   // la componente continua (e Nyquist, impacchettato qui) non serve
        return power
    }

    private func motionFeaturesAt(_ t: Double) -> ([Double], Bool) {
        guard let motion, motion.isRunning else { return (Array(repeating: 0, count: Self.motionFeatureCount), false) }
        var out: [Double] = []
        var ok = true
        for kind in [MotionSensor.Kind.accel, .gyro] {
            let base = motion.samples(kind, from: t - 0.25, to: t - 0.03)
            let win = motion.samples(kind, from: t - 0.03, to: t + 0.10)
            guard !base.isEmpty, !win.isEmpty else { out += Array(repeating: 0, count: 6); ok = false; continue }
            let n = Double(base.count)
            let b = (base.map(\.x).reduce(0, +) / n, base.map(\.y).reduce(0, +) / n, base.map(\.z).reduce(0, +) / n)
            var peaks: [Double] = [], rms: [Double] = []
            for (values, center) in [(win.map(\.x), b.0), (win.map(\.y), b.1), (win.map(\.z), b.2)] {
                let d = values.map { $0 - center }
                peaks.append(d.max(by: { abs($0) < abs($1) }) ?? 0)
                rms.append((d.map { $0 * $0 }.reduce(0, +) / Double(d.count)).squareRoot())
            }
            out += peaks + rms
        }
        return (out, ok)
    }

    private func closeGroup() {
        guard !open.isEmpty else { return }
        let taps = open
        open.removeAll()
        let n = Double(taps.count)
        var mean = [Double](repeating: 0, count: Self.featureCount)
        for tap in taps { for (i, v) in tap.features.enumerated() where i < mean.count { mean[i] += v / n } }
        let start = Date(timeIntervalSinceNow: taps[0].t - MotionSensor.now)
        onPattern?(TapPattern(taps: taps.count, date: start, features: mean,
                              hasMotion: taps.allSatisfy(\.motion), level: taps[0].level))
    }
}
