// tapprobe: fase 0 di Knock. Rileva i tap sul tavolo con il microfono, li raggruppa in
// doppi/tripli, calcola feature audio + accelerometro + giroscopio e le salva in CSV
// etichettate per zona. Nessun audio viene salvato.
// Uso: ./tapprobe [file.csv]    (default: data/taps.csv)
import Foundation
import AVFoundation
import Accelerate
import IOKit
import IOKit.hid

let motionOnly = CommandLine.arguments.contains("--sensori")

// MARK: - Tempo
var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func hostToSec(_ h: UInt64) -> Double { Double(h) * Double(timebase.numer) / Double(timebase.denom) / 1e9 }
func nowSec() -> Double { hostToSec(mach_absolute_time()) }

// MARK: - IMU (AppleSPU HID, accel usage 3, gyro usage 9, pagina 0xFF00)
struct IMUSample { let t: Double; let x: Double; let y: Double; let z: Double }

final class IMUStore {
    private let lock = NSLock()
    private var accel: [IMUSample] = []
    private var gyro: [IMUSample] = []
    var accelCount = 0, gyroCount = 0

    func add(kind: Int, _ s: IMUSample) {
        lock.lock(); defer { lock.unlock() }
        if kind == 3 { accel.append(s); accelCount += 1; if accel.count > 6000 { accel.removeFirst(3000) } }
        else { gyro.append(s); gyroCount += 1; if gyro.count > 6000 { gyro.removeFirst(3000) } }
    }
    func window(kind: Int, from: Double, to: Double) -> [IMUSample] {
        lock.lock(); defer { lock.unlock() }
        return (kind == 3 ? accel : gyro).filter { $0.t >= from && $0.t <= to }
    }
}
let imu = IMUStore()

/// Colpi dal solo accelerometro: scostamento dalla linea di base (vettore x, y, z) che salta sopra soglia.
/// Soglia = max(0,01 g, 8 deviazioni standard del rumore); il salto deve essere 2,5x il massimo che c'era PRIMA del colpo
/// (da 40 a 10 ms fa): un tap sale in qualche millisecondo, quindi i campioni appena precedenti fanno già parte del colpo.
final class MotionOnset {
    var base = (0.0, 0.0, 0.0), primed = 0
    var noiseVar = 1e-6
    var lastOnset = -1.0
    var ring = [Double](repeating: 0, count: 32), ringI = 0
    var onOnset: ((Double) -> Void)?
    var maxSeen = 0.0, lastThr = 0.0

    func feed(_ s: IMUSample) {
        if primed < 400 {
            let a = primed == 0 ? 1.0 : 0.02
            base = (base.0 + a * (s.x - base.0), base.1 + a * (s.y - base.1), base.2 + a * (s.z - base.2))
            primed += 1
            return
        }
        let d = (s.x - base.0, s.y - base.1, s.z - base.2)
        let mag = (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).squareRoot()
        let thr = max(0.01, 8 * noiseVar.squareRoot())
        // ring: ultimi 32 campioni (40 ms); si guarda solo la parte più vecchia, esclusi gli ultimi 8 (10 ms)
        var before = 0.0
        for k in 8..<ring.count { before = max(before, ring[(ringI - 1 - k + 2 * ring.count) % ring.count]) }
        let rise = mag > 2.5 * before
        ring[ringI] = mag; ringI = (ringI + 1) % ring.count
        maxSeen = max(maxSeen, mag); lastThr = thr
        if mag > thr && rise && s.t - lastOnset > 0.12 {
            lastOnset = s.t
            onOnset?(s.t)
            return
        }
        if s.t - lastOnset > 0.3 {
            base = (base.0 + 0.01 * d.0, base.1 + 0.01 * d.1, base.2 + 0.01 * d.2)
            if mag < thr / 2 { noiseVar = 0.995 * noiseVar + 0.005 * mag * mag }
        }
    }
}
let motionOnset = MotionOnset()
var motionTick: DispatchSourceTimer?

final class IMUContext { let kind: Int; let buf: UnsafeMutablePointer<UInt8>; init(kind: Int) { self.kind = kind; buf = .allocate(capacity: 64) } }
var imuContexts: [IMUContext] = []
var imuManagers: [IOHIDManager] = []   // vanno tenuti vivi, altrimenti i device si chiudono

func enableSPU(usage: Int) {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iter) == KERN_SUCCESS else { return }
    defer { IOObjectRelease(iter) }
    var svc = IOIteratorNext(iter)
    while svc != 0 {
        let up = IORegistryEntryCreateCFProperty(svc, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        let u = IORegistryEntryCreateCFProperty(svc, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        if up == 0xFF00 && u == usage {
            IORegistryEntrySetCFProperty(svc, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(svc, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(svc, "ReportInterval" as CFString, 1000 as CFNumber)
        }
        IOObjectRelease(svc)
        svc = IOIteratorNext(iter)
    }
}

func startIMU() {
    Thread {
        for usage in [3, 9] {
            enableSPU(usage: usage)
            let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(m, [kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: usage] as CFDictionary)
            IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
            imuManagers.append(m)
            guard let devs = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> else { continue }
            for d in devs {
                guard IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { continue }
                let ctx = IMUContext(kind: usage)
                imuContexts.append(ctx)
                IOHIDDeviceRegisterInputReportCallback(d, ctx.buf, 64, { context, _, _, _, _, r, len in
                    guard len >= 18, let context else { return }
                    let c = Unmanaged<IMUContext>.fromOpaque(context).takeUnretainedValue()
                    func i32(_ o: Int) -> Double {
                        Double(Int32(bitPattern: UInt32(r[o]) | UInt32(r[o+1]) << 8 | UInt32(r[o+2]) << 16 | UInt32(r[o+3]) << 24)) / 65536
                    }
                    let sample = IMUSample(t: nowSec(), x: i32(6), y: i32(10), z: i32(14))
                    imu.add(kind: c.kind, sample)
                    if motionOnly && c.kind == 3 { motionOnset.feed(sample) }
                }, Unmanaged.passUnretained(ctx).toOpaque())
                IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }
        }
        CFRunLoopRun()
    }.start()
}

// MARK: - Feature audio
let nBands = 24
final class Spectrum {
    let n: Int, bins: Int, sr: Double
    var cosT: [[Float]] = [], sinT: [[Float]] = []
    let window: [Float]
    init(n: Int, len: Int, sr: Double) {
        self.n = n; self.bins = n / 2; self.sr = sr
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: len, isHalfWindow: false)
        for k in 0..<bins {
            cosT.append((0..<len).map { Float(cos(2 * .pi * Double(k * $0) / Double(n))) })
            sinT.append((0..<len).map { Float(sin(2 * .pi * Double(k * $0) / Double(n))) })
        }
    }
    // DFT diretta con prodotti scalari vDSP: abbastanza veloce per una sonda (pochi ms a tap).
    func power(_ x: [Float]) -> [Float] {
        let w = vDSP.multiply(x, window)
        return (0..<bins).map { k in
            let re = vDSP.dot(w, cosT[k]), im = vDSP.dot(w, sinT[k])
            return re * re + im * im
        }
    }
}

struct TapRow {
    var label = "", t = 0.0
    var levelDB = 0.0, peakDB = 0.0, centroid = 0.0, decayMS = 0.0
    var bands: [Double] = []
    var imu: [Double] = []   // accel pk/rms xyz, gyro pk/rms xyz
    var imuN = 0
}

func imuFeatures(at t: Double) -> ([Double], Int) {
    var out: [Double] = []
    var n = 0
    for kind in [3, 9] {
        let base = imu.window(kind: kind, from: t - 0.25, to: t - 0.03)
        let win = imu.window(kind: kind, from: t - 0.03, to: t + 0.10)
        n += win.count
        guard !base.isEmpty, !win.isEmpty else { out += Array(repeating: 0, count: 6); continue }
        let bx = base.map(\.x).reduce(0, +) / Double(base.count)
        let by = base.map(\.y).reduce(0, +) / Double(base.count)
        let bz = base.map(\.z).reduce(0, +) / Double(base.count)
        var pk: [Double] = [], rms: [Double] = []
        for (vals, b) in [(win.map(\.x), bx), (win.map(\.y), by), (win.map(\.z), bz)] {
            let d = vals.map { $0 - b }
            pk.append(d.max(by: { abs($0) < abs($1) }) ?? 0)
            rms.append(sqrt(d.map { $0 * $0 }.reduce(0, +) / Double(d.count)))
        }
        out += pk + rms
    }
    return (out, n)
}

// MARK: - Rilevatore
final class Detector {
    let sr: Double
    let hop: Int, winLen: Int, tailLen: Int, refractory: Int
    let spectrum: Spectrum
    let bandEdges: [Int]
    var buf: [Float] = []        // segnale filtrato, finestra mobile
    var bufStart = 0             // indice assoluto di buf[0]
    var absIndex = 0
    var t0: Double? = nil
    var xPrev: Float = 0, yPrev: Float = 0
    let hpA: Float
    var acc: Float = 0, accN = 0
    var noise: Float = 1e-8
    var lastOnset = -1_000_000
    var recent = [Float](repeating: 0, count: 10)   // energie degli ultimi 50 ms
    var recentI = 0
    var pending: [Int] = []
    // pattern
    var label = ""
    var openRows: [TapRow] = []
    var lastTapT = -1.0
    var counts: [String: [Int: Int]] = [:]
    var out: FileHandle

    init(sr: Double, out: FileHandle) {
        self.sr = sr; self.out = out
        hop = Int(sr * 0.005); winLen = Int(sr * 0.04); tailLen = Int(sr * 0.12); refractory = Int(sr * 0.12)
        let rc = 1.0 / (2 * Double.pi * 100)   // passa-alto 100 Hz
        hpA = Float(rc / (rc + 1 / sr))
        var n = 1; while n < winLen { n *= 2 }
        spectrum = Spectrum(n: n, len: winLen, sr: sr)
        let fmax = min(20000, sr / 2 - 100)
        bandEdges = (0...nBands).map { i in
            let f = 80 * pow(fmax / 80, Double(i) / Double(nBands))
            return min(n / 2 - 1, max(1, Int(f / sr * Double(n))))
        }
    }

    func time(of idx: Int) -> Double { (t0 ?? 0) + Double(idx) / sr }

    func process(_ x: [Float], hostTime: UInt64) {
        if t0 == nil { t0 = hostTime != 0 ? hostToSec(hostTime) : nowSec() }
        buf.reserveCapacity(buf.count + x.count)
        for s in x {
            let y = hpA * (yPrev + s - xPrev)
            xPrev = s; yPrev = y
            buf.append(y)
            absIndex += 1
            acc += y * y; accN += 1
            if accN == hop {
                let e = acc / Float(hop)
                let onsetIdx = absIndex - hop
                // un tap è un salto di energia: almeno 8x (9 dB) sopra il massimo degli ultimi 50 ms.
                // La coda che si spegne dopo un tap non sale mai, quindi non viene più contata.
                let rise = e > 8 * (recent.max() ?? 0)
                recent[recentI] = e; recentI = (recentI + 1) % recent.count
                if rise && e > max(noise * 30, 1e-7) && onsetIdx - lastOnset > refractory {
                    lastOnset = onsetIdx
                    pending.append(onsetIdx)
                } else if onsetIdx - lastOnset > Int(sr * 0.15) && e < noise * 4 {
                    noise = 0.99 * noise + 0.01 * e
                }
                acc = 0; accN = 0
            }
        }
        // estrai feature quando c'è abbastanza coda (e l'IMU è arrivato)
        while let p = pending.first, absIndex >= p + tailLen {
            pending.removeFirst()
            extract(onset: p)
        }
        // chiudi pattern dopo 600 ms di silenzio
        if !openRows.isEmpty && time(of: absIndex) - lastTapT > 0.6 { closePattern() }
        // tieni 2 s di buffer
        let keep = Int(sr * 2)
        if buf.count > keep * 2 { let drop = buf.count - keep; buf.removeFirst(drop); bufStart += drop }
    }

    func extract(onset: Int) {
        let pre = Int(sr * 0.002)
        // allinea l'inizio al picco locale nei primi 5 ms dopo la soglia
        let s0 = max(bufStart, onset - pre) - bufStart
        guard s0 + tailLen <= buf.count else { return }
        let w = Array(buf[s0..<(s0 + winLen)])
        let p = spectrum.power(w)
        var row = TapRow()
        row.label = label
        row.t = time(of: onset)
        let total = Double(p.reduce(0, +)) + 1e-20
        row.levelDB = 10 * log10(total)
        row.peakDB = 20 * log10(Double(w.map { abs($0) }.max() ?? 0) + 1e-12)
        var c = 0.0
        for (k, v) in p.enumerated() { c += Double(k) * sr / Double(spectrum.n) * Double(v) }
        row.centroid = c / total
        var bands: [Double] = []
        for i in 0..<nBands {
            let lo = bandEdges[i], hi = max(bandEdges[i] + 1, bandEdges[i + 1])
            bands.append(10 * log10(Double(p[lo..<hi].reduce(0, +)) + 1e-20))
        }
        let mean = bands.reduce(0, +) / Double(nBands)
        row.bands = bands.map { $0 - mean }   // forma spettrale, indipendente dal volume
        // decadimento: frame da 2 ms, tempo dal picco a -20 dB
        let fr = Int(sr * 0.002)
        let tail = Array(buf[s0..<(s0 + tailLen)])
        let env = stride(from: 0, to: tail.count - fr, by: fr).map { i in Double(vDSP.sumOfSquares(tail[i..<(i + fr)])) / Double(fr) }
        if let pkI = env.indices.max(by: { env[$0] < env[$1] }) {
            let thr = env[pkI] / 100
            let endI = env[pkI...].firstIndex(where: { $0 < thr }) ?? env.count
            row.decayMS = Double(endI - pkI) * 2
        }
        (row.imu, row.imuN) = imuFeatures(at: row.t)
        if !openRows.isEmpty && row.t - lastTapT > 0.45 { closePattern() }
        openRows.append(row)
        lastTapT = row.t
    }

    /// Modalità solo sensori: un colpo dell'accelerometro all'istante t (le caratteristiche audio restano a zero).
    func addMotionTap(t: Double) {
        var row = TapRow()
        row.label = label
        row.t = t
        row.bands = Array(repeating: 0, count: nBands)
        (row.imu, row.imuN) = imuFeatures(at: t)
        if !openRows.isEmpty && row.t - lastTapT > 0.45 { closePattern() }
        openRows.append(row)
        lastTapT = row.t
    }

    var patternID = 0
    var verbose = false
    var onPattern: ((Int, Bool) -> Void)?
    func closePattern() {
        let n = openRows.count
        guard n > 0 else { return }
        patternID += 1
        counts[label, default: [:]][n, default: 0] += 1
        let name = n == 2 ? "doppio" : n == 3 ? "triplo" : "\(n) tap"
        let gaps = zip(openRows.dropFirst(), openRows).map { String(format: "%.0f", ($0.t - $1.t) * 1000) }.joined(separator: ", ")
        let imuOK = openRows.allSatisfy { $0.imuN > 0 }
        if verbose {
            print("  \(name)  [gap ms: \(gaps.isEmpty ? "-" : gaps)]  livello \(String(format: "%.0f", openRows[0].levelDB)) dB  imu \(imuOK ? "ok" : "assente")")
        }
        if !label.isEmpty { onPattern?(n, imuOK) }
        if !label.isEmpty {
            for (i, r) in openRows.enumerated() {
                let fields = [label, String(patternID), String(n), String(i), String(format: "%.4f", r.t),
                              String(format: "%.2f", r.levelDB), String(format: "%.2f", r.peakDB),
                              String(format: "%.1f", r.centroid), String(format: "%.1f", r.decayMS)]
                    + r.bands.map { String(format: "%.3f", $0) } + r.imu.map { String(format: "%.6f", $0) } + [String(r.imuN)]
                out.write((fields.joined(separator: ",") + "\n").data(using: .utf8)!)
            }
        }
        openRows.removeAll()
    }
}

// MARK: - Main
let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) ?? (motionOnly ? "data/taps_sensori.csv" : "data/taps.csv")
try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
if !FileManager.default.fileExists(atPath: path) {
    let header = ["label", "pattern", "pattern_size", "tap", "t", "level_db", "peak_db", "centroid", "decay_ms"]
        + (0..<nBands).map { "b\($0)" }
        + ["ax_pk", "ay_pk", "az_pk", "ax_rms", "ay_rms", "az_rms", "gx_pk", "gy_pk", "gz_pk", "gx_rms", "gy_rms", "gz_rms", "imu_n"]
    FileManager.default.createFile(atPath: path, contents: (header.joined(separator: ",") + "\n").data(using: .utf8))
}
guard let out = FileHandle(forWritingAtPath: path) else { print("impossibile scrivere \(path)"); exit(1) }
out.seekToEndOfFile()

let sem = DispatchSemaphore(value: 0)
var micOK = motionOnly
if !motionOnly {
    AVCaptureDevice.requestAccess(for: .audio) { micOK = $0; sem.signal() }
    sem.wait()
}
guard micOK else { print("Permesso microfono negato: Impostazioni di Sistema > Privacy e sicurezza > Microfono > Terminale."); exit(1) }

startIMU()

let engine = AVAudioEngine()
let queue = DispatchQueue(label: "tapprobe")
let detector: Detector
if motionOnly {
    print("Modalità SOLO SENSORI: il microfono non viene usato.")
    detector = Detector(sr: 48000, out: out)
    motionOnset.onOnset = { t in
        // le caratteristiche servono 100 ms dopo il colpo
        queue.asyncAfter(deadline: .now() + 0.13) { detector.addMotionTap(t: t) }
    }
    let tick = DispatchSource.makeTimerSource(queue: queue)
    tick.schedule(deadline: .now(), repeating: 0.05)
    tick.setEventHandler {
        if !detector.openRows.isEmpty && nowSec() - detector.lastTapT > 0.6 { detector.closePattern() }
    }
    tick.resume()
    motionTick = tick
} else {
    let input = engine.inputNode
    let fmt = input.outputFormat(forBus: 0)
    print("Microfono: \(Int(fmt.sampleRate)) Hz, \(fmt.channelCount) canali")
    detector = Detector(sr: fmt.sampleRate, out: out)
    input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buffer, when in
        guard let ch = buffer.floatChannelData else { return }
        let x = Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
        let h = when.isHostTimeValid ? when.hostTime : 0
        queue.async { detector.process(x, hostTime: h) }
    }
    do { try engine.start() } catch { print("Errore avvio audio: \(error)"); exit(1) }
}

Thread.sleep(forTimeInterval: 1.0)
print("IMU: accelerometro \(imu.accelCount) campioni, giroscopio \(imu.gyroCount) campioni nel primo secondo")

// MARK: - Sessione guidata: un pattern alla volta, ordine casuale
let zoneNames = ["alto_sx": "ALTO SINISTRA", "alto_dx": "ALTO DESTRA", "basso_sx": "BASSO SINISTRA", "basso_dx": "BASSO DESTRA"]
let zoneWhere = [
    "alto_sx": "a sinistra del Mac, all'altezza della cerniera dello schermo",
    "alto_dx": "a destra del Mac, all'altezza della cerniera dello schermo",
    "basso_sx": "a sinistra del Mac, all'altezza del bordo davanti (vicino a te)",
    "basso_dx": "a destra del Mac, all'altezza del bordo davanti (vicino a te)",
]

func map(_ zone: String?) -> String {
    func m(_ z: String) -> String { zone == z ? ">> X <<" : "   o   " }
    return """
              \(m("alto_sx"))       +-----------------+       \(m("alto_dx"))
                             |     schermo     |
                             +-----------------+  <- cerniera
                             |    tastiera     |
                             |    trackpad     |
              \(m("basso_sx"))       +-----------------+       \(m("basso_dx"))
                                     (tu sei qui)
    """
}

let resultSem = DispatchSemaphore(value: 0)
var lastSize = 0, lastIMU = false
detector.onPattern = { n, ok in lastSize = n; lastIMU = ok; resultSem.signal() }

func clear() { print("\u{1B}[2J\u{1B}[H", terminator: "") }

clear()
print("""
KNOCK, prova di fattibilità\(motionOnly ? " (SOLO SENSORI, niente microfono)" : "")

Preparazione (1 minuto):
  1. Mac aperto sul tavolo, non muoverlo per tutta la prova.
  2. Metti 4 segni (post-it, monete) sul tavolo nei punti o della mappa,
     a circa 10 cm dal bordo sinistro e destro del Mac.
  3. Ambiente tranquillo, mani lontane dalla tastiera.

\(map(nil))

Ti dirò ogni volta DOVE toccare e QUANTE volte (2 o 3 tap veloci, polpastrello,
forza normale). Dopo ogni gruppo passo da solo al successivo: niente Invio.
Sono 64 gruppi in ordine casuale, circa 4 minuti. Ctrl-C per interrompere.

Premi Invio quando sei pronto.
""")
_ = readLine()

var steps: [(String, Int)] = []
for z in ["alto_sx", "alto_dx", "basso_sx", "basso_dx"] { for n in [2, 3] { for _ in 0..<8 { steps.append((z, n)) } } }
steps.shuffle()

var done = 0, right = 0
var i = 0
while i < steps.count {
    let (z, n) = steps[i]
    let kind = n == 2 ? "doppio" : "triplo"
    clear()
    print("Gruppo \(i + 1) di \(steps.count)        pattern letti giusti finora: \(right)/\(done)\n")
    print(map(z))
    print("\n   \(zoneNames[z]!): \(zoneWhere[z]!)")
    print("\n   Tocca \(n == 2 ? "2 VOLTE  (tap tap)" : "3 VOLTE  (tap tap tap)")\n")
    Thread.sleep(forTimeInterval: 0.4)   // ignora rumori residui
    queue.sync { detector.closePattern(); detector.label = "\(z):\(kind)" }
    motionOnset.maxSeen = 0
    while resultSem.wait(timeout: .now()) == .success {}  // svuota segnali vecchi
    if resultSem.wait(timeout: .now() + 8) == .timedOut {
        queue.sync { detector.label = "" }
        if motionOnly {
            print(String(format: "   Non ho sentito nulla (colpo più forte: %.4f g, soglia %.4f g). Riprovo tra 2 secondi...", motionOnset.maxSeen, motionOnset.lastThr))
        } else {
            print("   Non ho sentito nulla. Tocca un po' più forte. Riprovo tra 2 secondi...")
        }
        Thread.sleep(forTimeInterval: 2)
        continue
    }
    queue.sync { detector.label = "" }
    done += 1
    if lastSize == n { right += 1; print("   OK, letto \(kind)\(lastIMU ? "" : " (accelerometro assente)")") }
    else { print("   Letto come \(lastSize) tap invece di \(n). Va bene lo stesso, è un dato utile.") }
    Thread.sleep(forTimeInterval: 1.0)
    i += 1
}

clear()
print("""
Ultima parte: falsi allarmi.
Per 30 secondi scrivi normalmente sulla tastiera (una frase qualsiasi), come faresti lavorando.
Premi Invio per iniziare.
""")
_ = readLine()
var noise = 0
detector.onPattern = { n, _ in if n == 2 || n == 3 { noise += 1 } }
queue.sync { detector.label = "rumore:nessuno" }
for s in stride(from: 30, to: 0, by: -1) { print("\r   scrivi... \(s) s   ", terminator: ""); fflush(stdout); Thread.sleep(forTimeInterval: 1) }
Thread.sleep(forTimeInterval: 0.7)
queue.sync { detector.closePattern(); detector.label = "" }
if !motionOnly { engine.stop() }
out.closeFile()
print("\n\nFinito. Pattern letti giusti: \(right)/\(done). Falsi doppi/tripli durante la digitazione: \(noise).")
print("Dati in \(path). Torna da Claude: lancio io l'analisi.")
