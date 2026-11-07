// Impostazioni › Azioni: cosa fa ogni interruttore. In alto il profilo ("Sempre" o un'app); sotto le quattro zone,
// ciascuna con doppio e triplo tap. Per un'app vale la sua azione; dove non ne ha, vale quella di "Sempre".

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ActionsSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var selected: UUID?
    @State private var accessibility = ActionRunner.hasAccessibility

    private var index: Int? {
        let id = selected ?? prefs.profiles.first?.id
        return prefs.profiles.firstIndex { $0.id == id }
    }

    var body: some View {
        Form {
            Section {
                Picker(L("Profilo"), selection: Binding(get: { selected ?? prefs.profiles.first?.id }, set: { selected = $0 })) {
                    ForEach(prefs.profiles) { p in Text(Self.name(p)).tag(Optional(p.id)) }
                }
                HStack {
                    Button(L("Aggiungi un'app…")) { addApp() }
                    if let i = index, !prefs.profiles[i].isGlobal {
                        Button(L("Rimuovi questo profilo")) {
                            prefs.profiles.remove(at: i)
                            selected = prefs.profiles.first?.id
                        }
                    }
                    Spacer()
                    Button(L("Ripristina i profili pronti")) {
                        prefs.profiles = ActionProfiles.defaults
                        selected = prefs.profiles.first?.id
                    }
                }
            } footer: {
                if let i = index, !prefs.profiles[i].isGlobal {
                    Footnote(L("Vale quando %@ è in primo piano. Dove qui non c'è un'azione, vale quella di Sempre.", Self.name(prefs.profiles[i])))
                } else {
                    Footnote(L("Sempre: vale in qualunque app, tranne dove il profilo dell'app in primo piano dice altro."))
                }
            }

            if let i = index {
                ForEach(Zone.allCases) { zone in
                    Section {
                        ForEach(TapCount.allCases) { count in
                            let s = TapSwitch(zone: zone, count: count)
                            LabeledContent(count.title) {
                                ActionEditor(action: Binding(
                                    get: { prefs.profiles[i].action(for: s) },
                                    set: { prefs.profiles[i].set($0, for: s) }
                                ))
                            }
                        }
                    } header: {
                        Label(zone.title, systemImage: Self.symbol(zone))
                    }
                }
            }

            Section {
                LabeledContent(L("Accessibilità")) {
                    if accessibility {
                        Label(L("Concesso"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.calm)
                    } else {
                        Button(L("Consenti…")) { ActionRunner.requestAccessibility() }
                    }
                }
            } footer: {
                Footnote(L("Serve solo per le azioni che premono un tasto: il tasto va all'app in primo piano, come se lo premessi tu. Nell'app di Claude e nel Terminale Invio approva la scelta evidenziata ed Esc rifiuta."))
            }
        }
        .onAppear { accessibility = ActionRunner.hasAccessibility }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibility = ActionRunner.hasAccessibility
        }
    }

    static func name(_ p: ActionProfile) -> String { p.isGlobal ? L("Sempre") : p.name }

    static func symbol(_ z: Zone) -> String {
        switch z {
        case .topLeft: "arrow.up.left.square"
        case .topRight: "arrow.up.right.square"
        case .bottomLeft: "arrow.down.left.square"
        case .bottomRight: "arrow.down.right.square"
        }
    }

    private func addApp() {
        guard let app = AppPicker.choose() else { return }
        if let existing = prefs.profiles.first(where: { $0.bundleIDs?.contains(app.bundleID) == true }) {
            selected = existing.id
            return
        }
        let p = ActionProfile(bundleIDs: [app.bundleID], name: app.name)
        prefs.profiles.append(p)
        selected = p.id
    }
}

private struct Footnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Scelta dell'azione: il tipo da un menu, poi il dettaglio (tasto, app, nome del Comando Rapido, indirizzo).
struct ActionEditor: View {
    @Binding var action: TapAction
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            detail
            Menu {
                ForEach(TapAction.Kind.allCases) { k in
                    Button { choose(k) } label: { Label(k.title, systemImage: k.symbol) }
                }
            } label: {
                Label(action.kind.title, systemImage: action.kind.symbol)
            }
            .fixedSize()
        }
        .onDisappear { stopRecording() }
    }

    @ViewBuilder private var detail: some View {
        switch action {
        case .key(let k):
            Button(recording ? L("Premi un tasto…") : k.label) { recording ? stopRecording() : startRecording() }
                .monospaced()
                .help(L("Clicca e premi il tasto o la combinazione da mandare"))
        case .openApp(_, let name):
            Button(name) { if let a = AppPicker.choose() { action = .openApp(bundleID: a.bundleID, name: a.name) } }
        case .shortcut(let name):
            TextField(L("Nome del Comando Rapido"), text: Binding(get: { name }, set: { action = .shortcut(name: $0) }))
                .frame(width: 150)
        case .openURL(let url):
            TextField("https://…", text: Binding(get: { url }, set: { action = .openURL($0) }))
                .frame(width: 150)
        default:
            EmptyView()
        }
    }

    private func choose(_ k: TapAction.Kind) {
        switch k {
        case .none: action = .none
        case .key: action = .key(.enter); startRecording()
        case .openApp:
            if let a = AppPicker.choose() { action = .openApp(bundleID: a.bundleID, name: a.name) }
        case .shortcut: action = .shortcut(name: "")
        case .openURL: action = .openURL("")
        case .toggleSystemMute: action = .toggleSystemMute
        case .toggleKnockMic: action = .toggleKnockMic
        case .stopListening: action = .stopListening
        }
    }

    private func startRecording() {
        stopRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            action = .key(KeyCombo(keyCode: e.keyCode, modifiers: mods.rawValue, label: KeyNames.label(e, mods)))
            stopRecording()
            return nil   // il tasto registrato non arriva alla finestra
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

enum KeyNames {
    static func label(_ e: NSEvent, _ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        let special: [UInt16: String] = [36: "⏎", 76: "⌤", 53: "⎋", 48: "⇥", 49: L("Spazio"), 51: "⌫", 117: "⌦",
                                         123: "←", 124: "→", 125: "↓", 126: "↑", 116: "⇞", 121: "⇟", 115: "↖", 119: "↘"]
        if let name = special[e.keyCode] { return s + name }
        let chars = (e.charactersIgnoringModifiers ?? "?").uppercased()
        return s + (chars.isEmpty ? "#\(e.keyCode)" : chars)
    }
}

@MainActor
enum AppPicker {
    /// Sceglie un'app da Applicazioni; nil se annullato.
    static func choose() -> (bundleID: String, name: String)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return (id, name)
    }
}
