// La pagina dei permessi: ogni cosa che serve a Knock, con lo stato, il pulsante per chiederla e una VERIFICA dal vivo
// (non basta che macOS dica "concesso": si ascolta davvero il microfono e si leggono davvero i sensori).
// Si apre da sola all'avvio se manca qualcosa di obbligatorio, e dal menu o da Impostazioni › Generale.
//
// Microfono: se macOS non mostra Knock in Impostazioni › Privacy › Microfono (permesso rimasto "negato" da una build
// precedente, o richiesta finita dietro le altre finestre), "Reimposta" cancella la decisione con
// `tccutil reset Microphone local.knock.app` (vale solo per Knock, non servono privilegi) e la richiesta riparte.

import AVFoundation
import AppKit
import Combine
import SwiftUI

@MainActor
final class PermissionsChecker: ObservableObject {
    enum Status: Equatable { case unknown, checking, ok, missing, failed }

    @Published private(set) var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var micTest = Status.unknown
    @Published private(set) var micLevel: Double = 0
    @Published private(set) var motionTest = Status.unknown
    @Published private(set) var motionRate = 0
    @Published private(set) var idleTest = Status.unknown
    @Published private(set) var message: String?

    private weak var model: AppModel?
    private var timer: AnyCancellable?

    init(model: AppModel) {
        self.model = model
    }

    /// Ricontrolla ogni secondo lo stato del microfono: cambia se lo attivi in Impostazioni di Sistema.
    func startWatching() {
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            let now = AVCaptureDevice.authorizationStatus(for: .audio)
            if now != self.mic {
                self.mic = now
                self.model?.refresh()
                if now == .authorized { Task { await self.testMicrophone() } }
            }
        }
    }

    func stopWatching() { timer = nil }

    static var allRequiredOK: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    func checkAll() async {
        mic = AVCaptureDevice.authorizationStatus(for: .audio)
        idleTest = TapEngine.idleSeconds.isFinite ? .ok : .failed
        if mic == .authorized { await testMicrophone() }
        await testMotion()
    }

    // MARK: - Microfono

    func requestMicrophone() {
        message = nil
        NSApp.activate()   // l'avviso di sistema compare davanti solo se l'app è attiva (Knock non ha Dock)
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.mic = AVCaptureDevice.authorizationStatus(for: .audio)
                    diag(.engine, "microphone request: \(ok), status \(self.mic.rawValue)")
                    self.model?.refresh()
                    if ok { Task { await self.testMicrophone() } }
                    else if self.mic == .denied {
                        self.message = L("macOS ha risposto di no. Attiva Knock in Impostazioni di Sistema › Privacy e sicurezza › Microfono; se Knock non c'è, usa Reimposta.")
                    }
                }
            }
        }
    }

    /// Cancella la decisione di macOS sul microfono per Knock e richiede di nuovo.
    func resetMicrophone() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Microphone", Bundle.main.bundleIdentifier ?? "local.knock.app"]
        do {
            try p.run()
            p.waitUntilExit()
            diag(.engine, "tccutil reset Microphone: exit \(p.terminationStatus)")
        } catch {
            message = error.localizedDescription
            return
        }
        mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if mic == .notDetermined {
            requestMicrophone()
        } else {
            message = L("Decisione cancellata. Se la richiesta non compare, chiudi e riapri Knock.")
        }
    }

    /// Ascolta 1,5 secondi e misura il livello: se arriva solo silenzio digitale, il permesso c'è solo sulla carta.
    func testMicrophone() async {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { micTest = .missing; return }
        micTest = .checking
        micLevel = 0
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { micTest = .failed; return }
        let box = LevelBox()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let ch = buffer.floatChannelData else { return }
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(ch[0][i])) }
            box.update(peak)
        }
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            micTest = .failed
            message = error.localizedDescription
            return
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        input.removeTap(onBus: 0)
        engine.stop()
        let peak = box.peak
        micLevel = Double(peak)
        micTest = peak > 0 ? .ok : .failed   // zero assoluto = macOS sta dando silenzio (permesso non effettivo)
        diag(.engine, "microphone test: peak \(peak)")
    }

    // MARK: - Sensore di movimento

    func testMotion() async {
        guard MotionSensor.isAvailable else { motionTest = .missing; return }
        motionTest = .checking
        if let running = model?.engine.motion, running.isRunning {
            let a = running.sampleCount
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            motionRate = running.sampleCount &- a
        } else {
            let s = MotionSensor()
            s.start()
            try? await Task.sleep(nanoseconds: 300_000_000)
            let a = s.sampleCount
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            motionRate = s.sampleCount &- a
            s.stop()
        }
        motionTest = motionRate > 50 ? .ok : .failed
        diag(.engine, "motion test: \(motionRate) samples/s")
    }
}

/// Il picco del test, scritto dal thread audio e letto dal main.
private final class LevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    func update(_ v: Float) { lock.lock(); value = max(value, v); lock.unlock() }
    var peak: Float { lock.lock(); defer { lock.unlock() }; return value }
}

struct PermissionsView: View {
    @ObservedObject var checker: PermissionsChecker
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    static let size = CGSize(width: 540, height: 520)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Permessi")).font(.title2.weight(.semibold))
            Text(L("Knock controlla da solo che tutto funzioni davvero. Quello che manca si sistema da qui."))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                microphoneRow
                motionRow
                PermissionRow(symbol: "keyboard", title: L("Riconoscere quando scrivi"),
                              detail: L("Per ignorare i tap mentre usi tastiera o trackpad. Non serve nessun permesso."),
                              status: checker.idleTest, optional: false) { EmptyView() }
                PermissionRow(symbol: "power", title: L("Apri all'accesso"),
                              detail: L("Facoltativo: Knock parte da solo quando accendi il Mac."),
                              status: launchAtLogin ? .ok : .missing, optional: true) {
                    Toggle("", isOn: Binding(get: { launchAtLogin }, set: { on in
                        LaunchAtLogin.set(on); launchAtLogin = LaunchAtLogin.isEnabled
                    })).labelsHidden().toggleStyle(.switch)
                }
            }

            if let m = checker.message {
                Text(m).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack {
                Button(L("Verifica di nuovo")) { Task { await checker.checkAll() } }
                Spacer()
                if checker.mic == .authorized && !model.isCalibrated {
                    Button(L("Calibra ora")) { close(); model.showCalibration() }
                        .keyboardShortcut(.defaultAction).glassProminentButton()
                } else {
                    Button(checker.mic == .authorized ? L("Fatto") : L("Più tardi"), action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .padding(.top, 12)
        .frame(width: Self.size.width, height: Self.size.height)
        .task { await checker.checkAll() }
        .onAppear { checker.startWatching() }
        .onDisappear { checker.stopWatching() }
    }

    private var microphoneRow: some View {
        let status: PermissionsChecker.Status = {
            switch checker.mic {
            case .authorized: return checker.micTest == .unknown ? .ok : checker.micTest
            case .notDetermined: return .missing
            default: return .failed
            }
        }()
        let detail: String = {
            switch checker.mic {
            case .authorized:
                switch checker.micTest {
                case .ok: return L("Concesso e verificato: il microfono sente.")
                case .failed: return L("Concesso, ma arriva solo silenzio. Prova Reimposta, poi riapri Knock.")
                case .checking: return L("Sto ascoltando per un secondo…")
                default: return L("Concesso.")
                }
            case .notDetermined: return L("Obbligatorio: è così che Knock sente i tap. Il suono non viene mai salvato.")
            default: return L("Negato. Attivalo in Impostazioni di Sistema; se Knock non compare nell'elenco, usa Reimposta.")
            }
        }()
        return PermissionRow(symbol: "mic", title: L("Microfono"), detail: detail, status: status, optional: false) {
            HStack(spacing: 6) {
                switch checker.mic {
                case .notDetermined:
                    Button(L("Consenti")) { checker.requestMicrophone() }.glassProminentButton()
                case .authorized:
                    if checker.micTest == .failed { Button(L("Reimposta")) { checker.resetMicrophone() } }
                default:
                    Button(L("Apri Impostazioni")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                    Button(L("Reimposta")) { checker.resetMicrophone() }
                }
            }
        }
    }

    private var motionRow: some View {
        let detail: String = {
            switch checker.motionTest {
            case .ok: return L("Funziona: %d letture al secondo.", checker.motionRate)
            case .missing: return L("Non presente su questo Mac: Knock userà solo il microfono.")
            case .failed: return L("Non risponde: Knock userà solo il microfono.")
            case .checking: return L("Sto leggendo il sensore…")
            case .unknown: return L("Facoltativo: aiuta a distinguere sinistra e destra.")
            }
        }()
        return PermissionRow(symbol: "gyroscope", title: L("Sensore di movimento"), detail: detail,
                             status: checker.motionTest, optional: true) { EmptyView() }
    }
}

private struct PermissionRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let status: PermissionsChecker.Status
    let optional: Bool
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    badge
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory()
        }
        .contentCard()
        .accessibilityElement(children: .contain)
    }

    /// Stato con icona e parola: il colore non è mai l'unico segnale.
    @ViewBuilder private var badge: some View {
        switch status {
        case .ok: Label(L("ok"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.calm)
        case .checking: ProgressView().controlSize(.mini)
        case .missing:
            if optional { Label(L("facoltativo"), systemImage: "minus.circle").foregroundStyle(.secondary) }
            else { Label(L("da concedere"), systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange) }
        case .failed:
            Label(optional ? L("non disponibile") : L("non funziona"), systemImage: "xmark.circle.fill")
                .foregroundStyle(optional ? Color.secondary : Palette.alarm)
        case .unknown: EmptyView()
        }
    }
}

@MainActor
final class PermissionsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let checker = PermissionsChecker(model: model)
            let w = TranslucentWindow.make(PermissionsView(checker: checker, model: model,
                                                           close: { [weak self] in self?.window?.close() }),
                                           size: PermissionsView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Permessi di Knock")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.window?.contentViewController = nil
                self?.window = nil
                AppModel.shared.refresh()
            }
        }
    }
}
