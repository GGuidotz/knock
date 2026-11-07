// Il motore: microfono + sensori di movimento -> rilevatore -> classificatore -> eventi.
// L'audio arriva da AVAudioEngine in blocchi da 1024 campioni; il thread audio copia il blocco e lo passa a una coda
// seriale, dove lavora tutto il resto. Gli eventi arrivano al chiamante sul main thread.
// Mentre usi tastiera o trackpad (ultimo input da meno di `typingGuard` secondi) i gruppi vengono ignorati: è la difesa
// principale contro i falsi allarmi (nella prova, 3 falsi doppi/tripli in 30 s di digitazione senza questa regola).

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

    var classifier: ZoneClassifier? {
        get { queue.sync { _classifier } }
        set { queue.async { self._classifier = newValue } }
    }
    var sensitivity: Double = 0.5 { didSet { applySensitivity() } }
    var useMotion = true
    /// Secondi dopo l'ultimo tasto o movimento del trackpad in cui i tap non contano (0 = mai ignorati).
    var typingGuard: Double = 1.0
    /// In calibrazione i gruppi vanno solo a `onPattern` e la regola della digitazione non vale.
    var calibrating = false

    let motion = MotionSensor()
    private var engine: AVAudioEngine?
    private var detector: TapDetector?
    private let queue = DispatchQueue(label: "local.knock.engine", qos: .userInteractive)
    private var _classifier: ZoneClassifier?
    private(set) var inputDescription = ""

    func start() {
        guard state != .running else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { state = .failed(L("Nessun microfono disponibile.")); return }
        inputDescription = "\(Int(format.sampleRate)) Hz, \(format.channelCount) ch"
        if useMotion && MotionSensor.isAvailable { motion.start() }
        let detector = TapDetector(sampleRate: format.sampleRate, motion: useMotion ? motion : nil)
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
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        motion.stop()
        queue.async { self.detector?.reset() }
        state = .stopped
    }

    private func applySensitivity() {
        // 0 = poco sensibile (soglia 60x il rumore di fondo), 1 = molto (12x). Predefinito 0.5 = 30x, come la prova.
        let threshold = Float(60 * pow(0.2, sensitivity))
        queue.async { self.detector?.threshold = threshold }
    }

    private func handle(_ p: TapPattern) {
        if calibrating {
            DispatchQueue.main.async { self.onPattern?(p) }
            return
        }
        DispatchQueue.main.async { self.onPattern?(p) }
        guard p.taps == 2 || p.taps == 3 else { return }
        if typingGuard > 0, Self.idleSeconds < typingGuard + 0.6 { return }   // +0,6 s: il gruppo dura fino a 600 ms
        let (zone, confidence) = _classifier?.classify(p.features) ?? (nil, 0)
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
