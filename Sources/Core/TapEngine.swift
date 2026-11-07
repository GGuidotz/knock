// Il motore: microfono e/o sensori di movimento -> rilevatore -> classificatore -> eventi.
// Modalità (ListeningMode): microfono + sensori (TapDetector con il movimento come caratteristiche in più), solo
// microfono, solo sensori (MotionTapDetector). Se il microfono è sospeso (azione "Spegni il microfono" o muto di
// sistema) e il Mac ha il sensore, il motore passa da solo ai soli sensori: così un tap può riaccenderlo.
// L'audio arriva da AVAudioEngine in blocchi da 1024 campioni; il thread audio copia il blocco e lo passa a una coda
// seriale, dove lavora tutto il resto. Gli eventi arrivano al chiamante sul main thread.
// Mentre usi tastiera o trackpad (ultimo input da meno di `typingGuard` secondi) i gruppi vengono ignorati.

import AVFAudio
import Foundation
import IOKit

final class TapEngine {
    enum State: Equatable { case stopped, running, failed(String) }

    private(set) var state = State.stopped
    /// Ogni gruppo chiuso, prima della classificazione (serve alla calibrazione).
    var onPattern: ((TapPattern) -> Void)?
    /// Ogni gruppo da 2 o 3 tap classificato (anche con zona sconosciuta).
    var onEvent: ((TapEvent) -> Void)?

    /// I classificatori per modalità; si usa quello della modalità in cui il motore sta ascoltando.
    var classifiers: [ListeningMode: ZoneClassifier] {
        get { queue.sync { _classifiers } }
        set { queue.async { self._classifiers = newValue } }
    }
    var sensitivity: Double = 0.5 { didSet { applySensitivity() } }
    /// La modalità scelta nelle impostazioni.
    var mode = ListeningMode.hybrid
    /// Il microfono è sospeso (azione o muto di sistema): si ascolta con i soli sensori, se ci sono.
    var micSuspended = false
    /// Secondi dopo l'ultimo tasto o movimento del trackpad in cui i tap non contano (0 = mai ignorati).
    var typingGuard: Double = 1.0
    /// In calibrazione i gruppi vanno solo a `onPattern` e la regola della digitazione non vale.
    var calibrating = false

    let motion = MotionSensor()
    private var engine: AVAudioEngine?
    private var detector: TapDetector?
    private var motionDetector: MotionTapDetector?
    private let queue = DispatchQueue(label: "local.knock.engine", qos: .userInteractive)
    private var _classifiers: [ListeningMode: ZoneClassifier] = [:]
    private var _activeMode = ListeningMode.hybrid
    private(set) var inputDescription = ""

    /// La modalità in cui si ascolta davvero adesso (può essere "solo sensori" se il microfono è sospeso).
    var effectiveMode: ListeningMode {
        let hasMotion = MotionSensor.isAvailable
        if !hasMotion { return .micOnly }
        if micSuspended { return .motionOnly }
        return mode
    }

    /// Modalità attiva mentre il motore gira.
    var activeMode: ListeningMode { queue.sync { _activeMode } }

    func start() {
        guard state != .running else { return }
        let m = effectiveMode
        if micSuspended && !MotionSensor.isAvailable {
            state = .failed(L("Microfono spento e nessun sensore di movimento su questo Mac."))
            return
        }
        queue.sync { _activeMode = m }
        if m.usesMotion { motion.start() }

        if m == .motionOnly {
            let d = MotionTapDetector(motion: motion, queue: queue)
            d.onPattern = { [weak self] p in self?.handle(p) }
            motionDetector = d
            d.start()
            inputDescription = "motion only"
            state = .running
            applySensitivity()
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            motion.stop()
            state = .failed(L("Nessun microfono disponibile."))
            return
        }
        inputDescription = "\(Int(format.sampleRate)) Hz, \(format.channelCount) ch"
        let detector = TapDetector(sampleRate: format.sampleRate, motion: m.usesMotion ? motion : nil)
        detector.onPattern = { [weak self] p in self?.handle(p) }
        self.detector = detector
        applySensitivity()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            guard let self, let ch = buffer.floatChannelData else { return }
            let x = Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
            let host = when.isHostTimeValid ? when.hostTime : 0
            self.queue.async { self.detector?.process(x, hostTime: host) }
        }
        do {
            try engine.start()
            self.engine = engine
            state = .running
        } catch {
            input.removeTap(onBus: 0)
            motion.stop()
            self.detector = nil
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        motionDetector?.stop()
        motionDetector = nil
        motion.stop()
        queue.async { self.detector?.reset(); self.detector = nil }
        state = .stopped
    }

    /// Riavvia se la modalità effettiva è cambiata (per esempio dopo aver sospeso il microfono).
    func restartIfNeeded() {
        guard state == .running, activeMode != effectiveMode else { return }
        stop()
        start()
    }

    private func applySensitivity() {
        // Microfono: 0 = poco sensibile (soglia 60x il rumore di fondo), 1 = molto (12x); 0,5 = 30x, come la prova.
        let threshold = Float(60 * pow(0.2, sensitivity))
        // Sensori: soglia minima da 0,012 g (0) a 0,005 g (1); 0,5 = circa 0,008 g.
        let motionThreshold = 0.012 * pow(0.005 / 0.012, sensitivity)
        queue.async {
            self.detector?.threshold = threshold
            self.motionDetector?.minThreshold = motionThreshold
        }
    }

    private func handle(_ p: TapPattern) {
        DispatchQueue.main.async { self.onPattern?(p) }
        if calibrating { return }
        guard p.taps == 2 || p.taps == 3 else { return }
        if typingGuard > 0, Self.idleSeconds < typingGuard + 0.6 { return }   // +0,6 s: il gruppo dura fino a 600 ms
        let (zone, confidence) = _classifiers[_activeMode]?.classify(p.features) ?? (nil, 0)
        let event = TapEvent(date: p.date, taps: p.taps, zone: zone, confidence: confidence)
        DispatchQueue.main.async { self.onEvent?(event) }
    }

    /// Secondi dall'ultimo input di tastiera, mouse o trackpad (IOHIDSystem, nessun permesso).
    static var idleSeconds: Double {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iter) == KERN_SUCCESS
        else { return .infinity }
        defer { IOObjectRelease(iter) }
        let entry = IOIteratorNext(iter)
        guard entry != 0 else { return .infinity }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return .infinity }
        return value.doubleValue / 1e9
    }
}
