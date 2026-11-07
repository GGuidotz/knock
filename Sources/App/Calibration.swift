// La calibrazione guidata, come la prova di fattibilità che è piaciuta: una mappa del tavolo con la zona da toccare,
// "tocca 2 volte" o "tocca 3 volte", e si passa da soli al gruppo dopo. 6 gruppi per zona (3 doppi e 3 tripli) in
// ordine casuale: 24 gruppi, circa un minuto e mezzo. Alla fine l'accuratezza stimata e "Salva".
// I gruppi letti con un numero di tap diverso da quello chiesto contano lo stesso per la zona: la firma del punto c'è.

import AppKit
import SwiftUI

@MainActor
final class CalibrationSession: ObservableObject {
    enum Phase: Equatable { case intro, running, done, failed(String) }

    struct Step: Equatable { let zone: Zone; let taps: Int }

    @Published private(set) var phase = Phase.intro
    @Published private(set) var index = 0
    @Published private(set) var feedback = ""
    /// Il classificatore della modalità in cui si è calibrato (quello di cui si mostra l'accuratezza).
    @Published private(set) var result: ZoneClassifier?
    /// Tutti quelli ricavati dagli stessi esempi (con microfono + sensori: anche solo microfono e solo sensori).
    private var trained: [ListeningMode: ZoneClassifier] = [:]
    @Published private(set) var mode = ListeningMode.hybrid
    @Published private(set) var heard = false

    let steps: [Step]
    private var samples: [CalibrationSample] = []
    private var motionSeen = 0
    private weak var model: AppModel?
    private var waitTask: Task<Void, Never>?
    private var acceptAfter = Date.distantPast

    static let perZone = 6

    init(model: AppModel) {
        self.model = model
        var s: [Step] = []
        for z in Zone.allCases { for i in 0..<Self.perZone { s.append(Step(zone: z, taps: i % 2 == 0 ? 2 : 3)) } }
        steps = s.shuffled()
    }

    var current: Step? { phase == .running && index < steps.count ? steps[index] : nil }

    func start() {
        guard let model else { return }
        samples = []; motionSeen = 0; index = 0; result = nil
        phase = .running
        feedback = ""
        acceptAfter = Date().addingTimeInterval(0.6)
        model.beginCalibration { [weak self] p in self?.received(p) }
        if model.engineState != .running {
            if case .failed(let why) = model.engineState {
                phase = .failed(L("Non riesco ad ascoltare: %@", why))
            } else {
                phase = .failed(L("Serve il permesso del microfono: Impostazioni di Sistema › Privacy e sicurezza › Microfono."))
            }
            model.endCalibration(result: nil)
            return
        }
        armTimeout()
    }

    /// Chiude senza salvare (Interrompi, o finestra chiusa prima di Salva).
    func cancel() {
        waitTask?.cancel()
        if phase == .running || phase == .done { model?.endCalibration(result: nil) }
        phase = .intro
    }

    func save() {
        model?.endCalibration(result: trained)
        phase = .intro   // già chiusa: la finestra che si chiude non deve annullare nulla
    }

    private func armTimeout() {
        waitTask?.cancel()
        let i = index
        waitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, let self, self.index == i, self.phase == .running else { return }
            self.feedback = L("Non ho sentito nulla: tocca un po' più forte, sempre sullo stesso punto.")
            self.armTimeout()
        }
    }

    private func received(_ p: TapPattern) {
        guard let step = current, Date() > acceptAfter else { return }
        // Un colpo isolato è quasi sempre un rumore: si aspetta il gruppo vero.
        guard p.taps >= 2 else { return }
        samples.append(CalibrationSample(zone: step.zone, features: p.features))
        if p.hasMotion { motionSeen += 1 }
        feedback = p.taps == step.taps ? L("Bene.") : L("Letto come %d tap: va bene lo stesso.", p.taps)
        heard.toggle()
        index += 1
        acceptAfter = Date().addingTimeInterval(0.8)
        if index >= steps.count { finish() } else { armTimeout() }
    }

    private func finish() {
        waitTask?.cancel()
        mode = model?.engine.activeMode ?? .hybrid
        trained = CalibrationStore.train(samples, mode: mode, motionSeen: motionSeen > samples.count / 2)
        guard let c = trained[mode] else {
            phase = .failed(L("Non ho abbastanza esempi per ogni zona. Riprova."))
            model?.endCalibration(result: nil)
            return
        }
        result = c
        phase = .done
    }
}

struct CalibrationView: View {
    @ObservedObject var session: CalibrationSession
    let close: () -> Void

    static let size = CGSize(width: 520, height: 470)

    var body: some View {
        VStack(spacing: 18) {
            switch session.phase {
            case .intro: intro
            case .running: running
            case .done: done
            case .failed(let why): failed(why)
            }
        }
        .padding(28)
        .padding(.top, 10)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Text(L("Calibrazione")).font(.title2.weight(.semibold))
            TableMap(highlight: nil)
            Text(L("Metti quattro segni sul tavolo (post-it o monete) nei punti della mappa, a circa 10 cm dal Mac. Ti dirò ogni volta dove toccare e quante volte. Non spostare il Mac durante la calibrazione."))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("%d gruppi, circa un minuto e mezzo.", session.steps.count))
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button(L("Annulla"), action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Inizia")) { session.start() }.keyboardShortcut(.defaultAction).glassProminentButton()
            }
        }
    }

    private var running: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(session.index), total: Double(session.steps.count))
            Text(L("Gruppo %d di %d", min(session.index + 1, session.steps.count), session.steps.count))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            if let step = session.current {
                TableMap(highlight: step.zone)
                Text(step.zone.hint).font(.callout).multilineTextAlignment(.center)
                Text(step.taps == 2 ? L("Tocca 2 volte") : L("Tocca 3 volte"))
                    .font(.system(size: 26, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
            }
            Text(session.feedback).foregroundStyle(.secondary).frame(height: 20)
            Spacer()
            HStack {
                Button(L("Interrompi")) { session.cancel(); close() }.keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Palette.calm)
                .accessibilityHidden(true)
            Text(L("Calibrazione finita")).font(.title2.weight(.semibold))
            if let r = session.result {
                Text(L("Zone riconosciute negli esempi: %d%%", Int((r.accuracy * 100).rounded())))
                    .font(.title3.monospacedDigit())
                Text(r.accuracy >= 0.85
                     ? L("Bene. Da ora i tap in queste zone diventano interruttori.")
                     : L("Così così: prova a toccare sempre lo stesso punto, un po' più deciso, e ricalibra."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                if session.mode == .motionOnly {
                    Text(L("Calibrazione per l'ascolto con i soli sensori.")).font(.callout).foregroundStyle(.secondary)
                } else if !r.usesMotion {
                    Text(L("Il sensore di movimento non ha risposto: uso solo il microfono."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack {
                Button(L("Rifai")) { session.start() }
                Spacer()
                Button(L("Salva")) { session.save(); close() }.keyboardShortcut(.defaultAction).glassProminentButton()
            }
        }
    }

    private func failed(_ why: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(why).multilineTextAlignment(.center)
            Spacer()
            HStack {
                Button(L("Chiudi"), action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Riprova")) { session.start() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// La mappa del tavolo: il Mac al centro e le quattro zone; quella da toccare è piena e con l'etichetta.
struct TableMap: View {
    let highlight: Zone?

    var body: some View {
        HStack(spacing: 34) {
            VStack(spacing: 46) { dot(.topLeft); dot(.bottomLeft) }
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary, lineWidth: 1.5)
                    .frame(width: 120, height: 62)
                    .overlay(Text(L("schermo")).font(.caption).foregroundStyle(.secondary))
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    .frame(width: 130, height: 58)
                    .overlay(Text(L("tastiera")).font(.caption).foregroundStyle(.secondary))
            }
            VStack(spacing: 46) { dot(.topRight); dot(.bottomRight) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(highlight.map { L("Tocca: %@", $0.title) } ?? L("Mappa delle quattro zone"))
    }

    private func dot(_ zone: Zone) -> some View {
        let on = highlight == zone
        return ZStack {
            Circle().fill(on ? Color.accentColor : Color.clear).frame(width: 34, height: 34)
            Circle().strokeBorder(on ? Color.accentColor : Color.secondary, lineWidth: on ? 3 : 1.5).frame(width: 34, height: 34)
            if on { Image(systemName: "hand.tap.fill").foregroundStyle(.white).font(.system(size: 15)) }
        }
        .frame(width: 44, height: 44)
    }
}

@MainActor
final class CalibrationWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var session: CalibrationSession?

    func show(model: AppModel) {
        if window == nil {
            let s = CalibrationSession(model: model)
            session = s
            let w = TranslucentWindow.make(CalibrationView(session: s, close: { [weak self] in self?.window?.close() }),
                                           size: CalibrationView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Calibrazione di Knock")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.session?.cancel()
                self?.session = nil
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
    }
}
