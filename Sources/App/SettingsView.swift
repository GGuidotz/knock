// Impostazioni (⌘,): cinque schede, con la barra a capsula di Sguardo che galleggia in fondo. Generale, Interruttori
// (calibrazione, sensibilità, prova dal vivo), Azioni, Aggiornamenti e Feedback come nelle altre app. Righe, gruppi e
// pulsanti sono di Sguardo (Vendor/Sguardo).

import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    static let size = CGSize(width: 580, height: 620)

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    init(model: AppModel) {
        self.model = model
        prefs = model.prefs
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch model.settingsTab {
                case .general: GeneralSettings(model: model, prefs: prefs)
                case .switches: SwitchesSettings(model: model, prefs: prefs)
                case .actions: ActionsSettings(model: model, prefs: prefs)
                case .updates: UpdatesSettings(updater: model.updater, prefs: prefs)
                case .feedback: FeedbackSettings(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // La barra delle schede galleggia in fondo: le righe ci scorrono sotto (SGPage lascia lo spazio).
            SettingsTabBar(selection: $model.settingsTab)
                .padding(.bottom, SG.Size.tabBarBottomInset)
        }
        // In alto, sotto i semafori della finestra, il contenuto sfuma invece di tagliarsi di netto.
        .overlay(alignment: .top) { SGProgressiveBlur() }
        .frame(width: Self.size.width, height: Self.size.height)
        // La barra del titolo è trasparente e la vista occupa tutta la finestra: senza questo la zona sicura in alto
        // spinge giù tutto e la barra delle schede finisce sul bordo inferiore.
        .ignoresSafeArea()
        .sguardoAccent(default: .knock)
        .id(prefs.language)
    }
}

// MARK: - Generale

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @State private var usage = SystemInfo.ownUsage
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        SGPage {
            SGSection {
                SGToggleRow(L("In ascolto"), isOn: $prefs.listening)
                    .disabled(!model.isCalibrated)
                SGDivider()
                SGToggleRow(L("Apri all'accesso"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        loginError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                if let loginError {
                    SGRowBlock { SGFootnote(loginError) }
                }
                SGDivider()
                SGMenuRow(L("Lingua"), selection: $prefs.language,
                          options: AppLanguage.allCases.map { (value: $0, title: $0.title) })
                SGDivider()
                SGAccentRow(L("Colore d'accento"),
                            options: (app: L("Colore dell'app"), system: L("Colore di sistema"), custom: L("Personalizzato")),
                            appDefault: .knock)
            } footer: {
                SGFootnote(L("Mentre Knock ascolta, macOS mostra il pallino arancione del microfono nella barra dei menu. Il suono resta in memoria per meno di due secondi e non viene mai salvato né inviato."))
            }

            SGSection {
                SGLabeledRow {
                    Text(L("Microfono"))
                } trailing: {
                    permissionLabel
                }
                SGDivider()
                SGRowBlock {
                    Button(L("Controlla i permessi…")) { model.showPermissions() }
                        .buttonStyle(.sgSecondary)
                }
                SGDivider()
                SGValueRow(L("Sensore di movimento"),
                           value: MotionSensor.isAvailable ? (model.engine.motion.isRunning ? L("In uso") : L("Disponibile"))
                                                           : L("Non presente su questo Mac"))
                SGDivider()
                SGValueRow(L("Consumo di Knock"),
                           value: usage.map { L("%@%% di CPU · %d MB", String(format: "%.1f", $0.cpu), Int($0.memory / 1_048_576)) } ?? "–")
                SGDivider()
                SGRowBlock {
                    Button(L("Rivedi la guida iniziale")) { model.showOnboarding() }
                        .buttonStyle(.sgSecondary)
                }
            } footer: {
                SGFootnote(L("L'obiettivo è restare sotto l'1% di CPU mentre ascolta. In pausa Knock non usa né microfono né sensori."))
            }
        }
        .onReceive(timer) { _ in usage = SystemInfo.ownUsage }
    }

    @ViewBuilder private var permissionLabel: some View {
        switch model.micPermission {
        case .authorized:
            Label(L("Concesso"), systemImage: "checkmark.circle.fill")
                .font(SG.Font.body)
                .foregroundStyle(Palette.calm)
        case .notDetermined:
            Button(L("Consenti")) { model.requestMicrophone { _ in } }
                .buttonStyle(.sgSecondary)
        default:
            Button(L("Apri Impostazioni")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
            .buttonStyle(.sgSecondary)
        }
    }
}

// MARK: - Interruttori

private struct SwitchesSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    var body: some View {
        SGPage {
            SGSection {
                // Come SGMenuRow, ma con le modalità che usano il sensore spente dove il Mac non ce l'ha.
                SGLabeledRow {
                    Text(L("Ascolta con"))
                } trailing: {
                    SGPickerPill(prefs.mode.title) {
                        Picker(L("Ascolta con"), selection: $prefs.mode) {
                            ForEach(ListeningMode.allCases) { m in
                                Text(m.title).tag(m).disabled(m.usesMotion && !MotionSensor.isAvailable)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    .accessibilityLabel(L("Ascolta con"))
                }
                if model.micSuspended && MotionSensor.isAvailable {
                    SGDivider()
                    SGValueRow(L("Adesso"),
                               value: prefs.knockMicOff ? L("Microfono di Knock spento: solo sensori") : L("Microfono di sistema muto: solo sensori"))
                    if prefs.knockMicOff {
                        SGDivider()
                        SGRowBlock {
                            Button(L("Riaccendi il microfono di Knock")) { prefs.knockMicOff = false }
                                .buttonStyle(.sgSecondary)
                        }
                    }
                }
            } footer: {
                SGFootnote(L("Con i soli sensori non serve il microfono e non compare il pallino arancione, ma i tap vicino alla cerniera si sentono peggio (nella prova: gruppi giusti 77%, zone 86%). Ogni modalità ha la sua calibrazione; calibrando con microfono e sensori si preparano anche le altre due."))
            }

            SGSection(L("Calibrazione")) {
                ForEach(Array(ListeningMode.allCases.enumerated()), id: \.element) { index, m in
                    if index > 0 { SGDivider() }
                    SGValueRow(m.title) {
                        if let c = model.classifiers[m] {
                            Text(L("%d%% negli esempi · %@", Int((c.accuracy * 100).rounded()),
                                   c.createdAt.formatted(date: .abbreviated, time: .shortened)))
                        } else {
                            Text(L("Da fare")).foregroundStyle(m == model.effectiveMode ? Color.orange : SG.Ink.secondary)
                        }
                    }
                }
                SGDivider()
                SGRowBlock {
                    HStack {
                        Button(model.isCalibrated ? L("Ricalibra…") : L("Calibra…")) { model.showCalibration() }
                            .buttonStyle(.sgSecondary)
                        if !model.classifiers.isEmpty {
                            Button(L("Dimentica tutte")) { model.forgetCalibration() }
                                .buttonStyle(.sgSecondary)
                        }
                    }
                }
            } footer: {
                SGFootnote(L("La calibrazione si fa nella modalità scelta sopra. Ricalibra se sposti il Mac o cambi tavolo: la firma di ogni punto dipende dalla superficie."))
            }

            SGSection {
                SGLabeledRow {
                    Text(L("Sensibilità"))
                } trailing: {
                    HStack(spacing: 8) {
                        Text(L("Bassa")).font(SG.Font.caption).foregroundStyle(SG.Ink.secondary).lineLimit(1).fixedSize()
                        Slider(value: $prefs.sensitivity, in: 0...1).frame(width: 180)
                        Text(L("Alta")).font(SG.Font.caption).foregroundStyle(SG.Ink.secondary).lineLimit(1).fixedSize()
                    }
                }
                SGDivider()
                SGToggleRow(L("Ignora i tap mentre scrivi"), isOn: $prefs.ignoreWhileTyping)
                SGDivider()
                SGToggleRow(L("Fai lampeggiare la voce nella barra"), isOn: $prefs.flashMenuBar)
                SGDivider()
                SGToggleRow(L("Suono breve quando scatta"), isOn: $prefs.sound)
            } footer: {
                SGFootnote(L("Se perde dei tap, alza la sensibilità; se scatta da solo, abbassala. Con \"Ignora i tap mentre scrivi\" non scatta nulla fino a un secondo dopo l'ultimo tasto."))
            }

            SGSection(L("Prova dal vivo")) {
                if model.events.isEmpty {
                    SGRowBlock {
                        Text(model.engineState == .running ? L("Tocca il tavolo: i tap riconosciuti compaiono qui.")
                                                           : L("Knock non è in ascolto."))
                            .foregroundStyle(SG.Ink.secondary)
                    }
                } else {
                    ForEach(Array(model.events.prefix(8).enumerated()), id: \.element.id) { index, e in
                        if index > 0 { SGDivider() }
                        SGLabeledRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(StatusItemController.describe(e))
                                if let a = e.actionTitle {
                                    Text(a).font(SG.Font.caption).foregroundStyle(SG.Ink.secondary)
                                }
                            }
                        } trailing: {
                            if e.zone != nil {
                                Text(L("%d%%", Int((e.confidence * 100).rounded())))
                                    .font(SG.Font.body)
                                    .monospacedDigit()
                                    .foregroundStyle(SG.Ink.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Aggiornamenti

private struct UpdatesSettings: View {
    @ObservedObject var updater: Updater
    @ObservedObject var prefs: Preferences
    private let current = Changelog.load().first

    var body: some View {
        SGPage {
            SGSection {
                SGToggleRow(L("Controlla automaticamente (ogni 6 ore)"), isOn: $prefs.autoCheckUpdates)
                SGDivider()
                SGValueRow(L("Versione installata"), value: updater.currentVersion)
                SGDivider()
                SGValueRow(L("Ultimo controllo")) {
                    if let last = updater.lastCheck { Text(last, style: .relative) } else { Text(L("Mai")) }
                }
                SGDivider()
                SGRowBlock {
                    HStack(spacing: 12) {
                        Button(L("Controlla ora")) { Task { await updater.check() } }
                            .buttonStyle(.sgSecondary)
                            .disabled(updater.state == .checking)
                        UpdateStateText(updater: updater)
                    }
                }
            }
            if updater.isUpdateAvailable {
                SGSection {
                    SGRowBlock { UpdateCard(updater: updater) }
                }
            }
            if let current {
                SGSection(L("Novità di questa versione")) {
                    SGRowBlock { ChangelogList(entries: [current]) }
                    SGDivider()
                    SGRowBlock {
                        Button(L("Mostra la schermata delle novità")) { AppModel.shared.showWhatsNew() }
                            .buttonStyle(.sgSecondary)
                    }
                }
            }
        }
    }
}

private struct UpdateStateText: View {
    @ObservedObject var updater: Updater
    @Environment(\.sgAccent) private var accent

    var body: some View {
        switch updater.state {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate:
            Label(L("Knock è aggiornato."), systemImage: "checkmark.circle.fill")
                .font(SG.Font.body).foregroundStyle(Palette.calm)
        case .available(let version):
            Label(L("Disponibile la versione %@", version), systemImage: "arrow.down.circle.fill")
                .font(SG.Font.body).foregroundStyle(accent.base)
        case .failed(let why):
            Text(why).font(SG.Font.body).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .available(let version) = updater.state {
                Label(L("Disponibile Knock %@", version), systemImage: "arrow.down.circle.fill")
                    .font(SG.Font.bodyEmphasis)
            }
            if !updater.news.isEmpty { ChangelogList(entries: updater.news) }
            Text(L("Per aggiornare, esegui nel Terminale:")).foregroundStyle(SG.Ink.secondary)
            Text(updater.command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SG.Fill.tile, in: .sgTile)
            HStack(spacing: 8) {
                Button(L("Copia comando")) { updater.copyCommand() }
                    .buttonStyle(.sgSecondary)
                Button(L("Aggiorna nel Terminale")) { updater.runInTerminal() }
                    .buttonStyle(.sgPrimary)
            }
            if let error = updater.terminalError {
                Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Feedback

private struct FeedbackSettings: View {
    @ObservedObject var model: AppModel
    @State private var status: String?
    @State private var showReport = false

    var body: some View {
        SGPage {
            SGSection {
                SGRowBlock {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Knock").font(SG.Font.title)
                            Text(L("Versione %@", "\(SystemInfo.version) (\(SystemInfo.build))"))
                                .foregroundStyle(SG.Ink.secondary)
                            Text(L("Il tavolo accanto al Mac diventa un pannello di interruttori."))
                                .foregroundStyle(SG.Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            SGSection(L("Feedback")) {
                FeedbackButton(symbol: "ladybug", title: L("Segnala un problema"),
                               detail: L("Su GitHub, con versione, macOS e modello del Mac già scritti.")) {
                    Feedback.openIssue(.problem)
                }
                SGDivider()
                FeedbackButton(symbol: "lightbulb", title: L("Suggerisci un'idea"),
                               detail: L("Un'azione da collegare a un interruttore, un tavolo dove non funziona, un modo migliore di calibrare.")) {
                    Feedback.openIssue(.idea)
                }
                SGDivider()
                FeedbackButton(symbol: "envelope", title: L("Scrivi un'email"), detail: Developer.email) {
                    Feedback.composeEmail()
                }
            } footer: {
                SGFootnote(L("GitHub è il canale preferito: le segnalazioni sono pubbliche, quindi non scrivere dati personali. Per qualcosa di privato usa l'email."))
            }

            SGSection(L("Diagnostica")) {
                SGRowBlock {
                    HStack(spacing: 8) {
                        Button(L("Copia report")) {
                            Feedback.copyReport(model: model)
                            status = L("Report copiato: incollalo nella segnalazione.")
                        }
                        .buttonStyle(.sgSecondary)
                        Button(L("Salva…")) { status = Feedback.saveReport(model: model) }
                            .buttonStyle(.sgSecondary)
                        Spacer()
                        Button(showReport ? L("Nascondi") : L("Mostra")) {
                            withAnimation(SG.Motion.respecting(SG.Motion.snappy)) { showReport.toggle() }
                        }
                        .buttonStyle(.sgSecondary)
                    }
                }
                if let status {
                    SGDivider()
                    SGRowBlock { SGFootnote(status) }
                }
                if showReport {
                    SGDivider()
                    SGRowBlock {
                        ScrollView {
                            Text(DiagnosticsReport.make(model: model))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                    }
                }
            } footer: {
                SGFootnote(L("Il report dice versione, Mac, stato del microfono e dei sensori, le tue scelte e quanti tap ha visto. Mai suoni, nomi di app o file."))
            }

            SGSection {
                SGRowBlock { DeveloperLinks() }
            }
        }
    }
}

private struct FeedbackButton: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void
    @Environment(\.sgAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(accent.base).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(SG.Font.body).foregroundStyle(SG.Ink.primary)
                    Text(detail).font(SG.Font.caption).foregroundStyle(SG.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(SG.Ink.tertiary)
            }
            .padding(.horizontal, SG.Space.rowInset)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: SG.Size.row, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}
