// Impostazioni (⌘,): quattro schede sotto una barra di vetro che galleggia. Generale, Interruttori (calibrazione,
// sensibilità, prova dal vivo), Aggiornamenti e Feedback come nelle altre app.

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
        Group {
            switch model.settingsTab {
            case .general: GeneralSettings(model: model, prefs: prefs)
            case .switches: SwitchesSettings(model: model, prefs: prefs)
            case .actions: ActionsSettings(model: model, prefs: prefs)
            case .updates: UpdatesSettings(updater: model.updater, prefs: prefs)
            case .feedback: FeedbackSettings(model: model)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsTabBar(selection: $model.settingsTab)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)
    }
}

private struct Footnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
        Form {
            Section {
                Toggle(L("In ascolto"), isOn: $prefs.listening)
                    .disabled(!model.isCalibrated)
                Toggle(L("Apri all'accesso"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        loginError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                if let loginError { Footnote(loginError) }
                Picker(L("Lingua"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Footnote(L("Mentre Knock ascolta, macOS mostra il pallino arancione del microfono nella barra dei menu. Il suono resta in memoria per meno di due secondi e non viene mai salvato né inviato."))
            }

            Section {
                LabeledContent(L("Microfono")) { permissionLabel }
                Button(L("Controlla i permessi…")) { model.showPermissions() }
                LabeledContent(L("Sensore di movimento")) {
                    Text(MotionSensor.isAvailable ? (model.engine.motion.isRunning ? L("In uso") : L("Disponibile"))
                                                  : L("Non presente su questo Mac"))
                }
                LabeledContent(L("Consumo di Knock")) {
                    Text(usage.map { L("%@%% di CPU · %d MB", String(format: "%.1f", $0.cpu), Int($0.memory / 1_048_576)) } ?? "–")
                        .monospacedDigit()
                }
                Button(L("Rivedi la guida iniziale")) { model.showOnboarding() }
            } footer: {
                Footnote(L("L'obiettivo è restare sotto l'1% di CPU mentre ascolta. In pausa Knock non usa né microfono né sensori."))
            }
        }
        .onReceive(timer) { _ in usage = SystemInfo.ownUsage }
    }

    @ViewBuilder private var permissionLabel: some View {
        switch model.micPermission {
        case .authorized:
            Label(L("Concesso"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.calm)
        case .notDetermined:
            Button(L("Consenti")) { model.requestMicrophone { _ in } }
        default:
            Button(L("Apri Impostazioni")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }
}

// MARK: - Interruttori

private struct SwitchesSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Picker(L("Ascolta con"), selection: $prefs.mode) {
                    ForEach(ListeningMode.allCases) { m in
                        Text(m.title).tag(m).disabled(m.usesMotion && !MotionSensor.isAvailable)
                    }
                }
                if model.micSuspended && MotionSensor.isAvailable {
                    LabeledContent(L("Adesso")) {
                        Text(prefs.knockMicOff ? L("Microfono di Knock spento: solo sensori") : L("Microfono di sistema muto: solo sensori"))
                            .foregroundStyle(.secondary)
                    }
                    if prefs.knockMicOff { Button(L("Riaccendi il microfono di Knock")) { prefs.knockMicOff = false } }
                }
            } footer: {
                Footnote(L("Con i soli sensori non serve il microfono e non compare il pallino arancione, ma i tap vicino alla cerniera si sentono peggio (nella prova: gruppi giusti 77%, zone 86%). Ogni modalità ha la sua calibrazione; calibrando con microfono e sensori si preparano anche le altre due."))
            }

            Section {
                ForEach(ListeningMode.allCases) { m in
                    LabeledContent(m.title) {
                        if let c = model.classifiers[m] {
                            Text(L("%d%% negli esempi · %@", Int((c.accuracy * 100).rounded()),
                                   c.createdAt.formatted(date: .abbreviated, time: .shortened)))
                                .monospacedDigit()
                        } else {
                            Text(L("Da fare")).foregroundStyle(m == model.effectiveMode ? Color.orange : Color.secondary)
                        }
                    }
                }
                HStack {
                    Button(model.isCalibrated ? L("Ricalibra…") : L("Calibra…")) { model.showCalibration() }
                    if !model.classifiers.isEmpty {
                        Button(L("Dimentica tutte")) { model.forgetCalibration() }
                    }
                }
            } header: {
                Text(L("Calibrazione"))
            } footer: {
                Footnote(L("La calibrazione si fa nella modalità scelta sopra. Ricalibra se sposti il Mac o cambi tavolo: la firma di ogni punto dipende dalla superficie."))
            }

            Section {
                LabeledContent(L("Sensibilità")) {
                    HStack {
                        Text(L("Bassa")).font(.caption).foregroundStyle(.secondary)
                        Slider(value: $prefs.sensitivity, in: 0...1).frame(width: 180)
                        Text(L("Alta")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(L("Ignora i tap mentre scrivi"), isOn: $prefs.ignoreWhileTyping)
                Toggle(L("Fai lampeggiare la voce nella barra"), isOn: $prefs.flashMenuBar)
                Toggle(L("Suono breve quando scatta"), isOn: $prefs.sound)
            } footer: {
                Footnote(L("Se perde dei tap, alza la sensibilità; se scatta da solo, abbassala. Con \"Ignora i tap mentre scrivi\" non scatta nulla fino a un secondo dopo l'ultimo tasto."))
            }

            Section {
                if model.events.isEmpty {
                    Text(model.engineState == .running ? L("Tocca il tavolo: i tap riconosciuti compaiono qui.")
                                                       : L("Knock non è in ascolto."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.events.prefix(8)) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(StatusItemController.describe(e))
                                Spacer()
                                if e.zone != nil {
                                    Text(L("%d%%", Int((e.confidence * 100).rounded())))
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            if let a = e.actionTitle { Text(a).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            } header: {
                Text(L("Prova dal vivo"))
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
        Form {
            Section {
                Toggle(L("Controlla automaticamente (ogni 6 ore)"), isOn: $prefs.autoCheckUpdates)
                LabeledContent(L("Versione installata"), value: updater.currentVersion)
                LabeledContent(L("Ultimo controllo")) {
                    if let last = updater.lastCheck { Text(last, style: .relative) } else { Text(L("Mai")) }
                }
                HStack {
                    Button(L("Controlla ora")) { Task { await updater.check() } }
                        .disabled(updater.state == .checking)
                    UpdateStateText(updater: updater)
                }
            }
            if updater.isUpdateAvailable {
                Section { UpdateCard(updater: updater) }
            }
            if let current {
                Section {
                    ChangelogList(entries: [current])
                    Button(L("Mostra la schermata delle novità")) { AppModel.shared.showWhatsNew() }
                } header: {
                    Text(L("Novità di questa versione"))
                }
            }
        }
    }
}

private struct UpdateStateText: View {
    @ObservedObject var updater: Updater

    var body: some View {
        switch updater.state {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate:
            Label(L("Knock è aggiornato."), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.calm)
        case .available(let version):
            Label(L("Disponibile la versione %@", version), systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
        case .failed(let why):
            Text(why).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .available(let version) = updater.state {
                Label(L("Disponibile Knock %@", version), systemImage: "arrow.down.circle.fill").font(.headline)
            }
            if !updater.news.isEmpty { ChangelogList(entries: updater.news) }
            Text(L("Per aggiornare, esegui nel Terminale:")).foregroundStyle(.secondary)
            Text(updater.command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            HStack {
                Button(L("Copia comando")) { updater.copyCommand() }
                Button(L("Aggiorna nel Terminale")) { updater.runInTerminal() }.glassProminentButton()
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
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Knock").font(.title2.weight(.semibold)).fontDesign(.rounded)
                        Text(L("Versione %@", "\(SystemInfo.version) (\(SystemInfo.build))")).foregroundStyle(.secondary)
                        Text(L("Il tavolo accanto al Mac diventa un pannello di interruttori.")).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                FeedbackButton(symbol: "ladybug", title: L("Segnala un problema"),
                               detail: L("Su GitHub, con versione, macOS e modello del Mac già scritti.")) {
                    Feedback.openIssue(.problem)
                }
                FeedbackButton(symbol: "lightbulb", title: L("Suggerisci un'idea"),
                               detail: L("Un'azione da collegare a un interruttore, un tavolo dove non funziona, un modo migliore di calibrare.")) {
                    Feedback.openIssue(.idea)
                }
                FeedbackButton(symbol: "envelope", title: L("Scrivi un'email"), detail: Developer.email) {
                    Feedback.composeEmail()
                }
            } header: {
                Text(L("Feedback"))
            } footer: {
                Footnote(L("GitHub è il canale preferito: le segnalazioni sono pubbliche, quindi non scrivere dati personali. Per qualcosa di privato usa l'email."))
            }
            Section {
                HStack {
                    Button(L("Copia report")) {
                        Feedback.copyReport(model: model)
                        status = L("Report copiato: incollalo nella segnalazione.")
                    }
                    Button(L("Salva…")) { status = Feedback.saveReport(model: model) }
                    Spacer()
                    Button(showReport ? L("Nascondi") : L("Mostra")) { showReport.toggle() }
                }
                if let status { Footnote(status) }
                if showReport {
                    ScrollView {
                        Text(DiagnosticsReport.make(model: model))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                }
            } header: {
                Text(L("Diagnostica"))
            } footer: {
                Footnote(L("Il report dice versione, Mac, stato del microfono e dei sensori, le tue scelte e quanti tap ha visto. Mai suoni, nomi di app o file."))
            }
            Section { DeveloperLinks() }
        }
    }
}

private struct FeedbackButton: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}
