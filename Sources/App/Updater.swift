// Aggiornamenti: all'avvio (dopo 30 s), ogni 6 ore e su richiesta legge VERSION e CHANGELOG.md dal ramo main di
// GGuidotz/knock. Se c'è una versione più nuova mostra le sue novità e il comando per aggiornare:
//   installato con Homebrew: brew update && brew upgrade --cask knock
//   compilato dai sorgenti: cd '<cartella del clone>' && git pull && ./build.sh --install
// "Aggiorna nel Terminale" apre il Terminale ed esegue il comando (la prima volta macOS chiede il permesso Automazione).
// Stesso schema di Nod.

import AppKit
import Foundation

@MainActor
final class Updater: ObservableObject {
    enum Channel: String { case source, homebrew }

    enum State: Equatable, CustomStringConvertible {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case failed(String)

        var description: String {
            switch self {
            case .idle: "idle"
            case .checking: "checking"
            case .upToDate: "up to date"
            case .available(let v): "available \(v)"
            case .failed(let why): "failed: \(why)"
            }
        }
    }

    @Published private(set) var state = State.idle
    @Published private(set) var lastCheck: Date?
    @Published private(set) var news: [ChangelogEntry] = []
    @Published private(set) var terminalError: String?

    static let versionURL = URL(string: "https://raw.githubusercontent.com/GGuidotz/knock/main/VERSION")!
    static let changelogURL = URL(string: "https://raw.githubusercontent.com/GGuidotz/knock/main/CHANGELOG.md")!

    private let prefs: Preferences
    private var timer: Timer?

    init(prefs: Preferences) { self.prefs = prefs }

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var isUpdateAvailable: Bool { if case .available = state { return true }; return false }

    static var channel: Channel {
        let fm = FileManager.default
        return fm.fileExists(atPath: "/opt/homebrew/Caskroom/knock") || fm.fileExists(atPath: "/usr/local/Caskroom/knock")
            ? .homebrew : .source
    }

    /// La cartella del clone da cui è stata compilata questa copia (scritta da build.sh).
    static var sourcePath: String? { Bundle.main.infoDictionary?["KnockSourcePath"] as? String }

    var command: String {
        switch Self.channel {
        case .homebrew:
            return "brew update && brew upgrade --cask knock"
        case .source:
            let path = Self.sourcePath ?? "~/Developer/knock"
            return "cd '\(path.replacingOccurrences(of: "'", with: "'\\''"))' && git pull && ./build.sh --install"
        }
    }

    func start() {
        guard timer == nil else { return }
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if prefs.autoCheckUpdates { await check() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.prefs.autoCheckUpdates else { return }
                Task { await self.check() }
            }
        }
    }

    func check() async {
        state = .checking
        do {
            var request = URLRequest(url: Self.versionURL, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw URLError(.badServerResponse) }
            let latest = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            lastCheck = Date()
            if Version(latest) > Version(currentVersion) {
                let (log, _) = try await URLSession.shared.data(from: Self.changelogURL)
                news = Changelog.entries(after: currentVersion, upTo: latest,
                                         in: Changelog.parse(String(decoding: log, as: UTF8.self)))
                state = .available(version: latest)
            } else {
                news = []
                state = .upToDate
            }
            diag(.update, "checked: current \(currentVersion), latest \(latest)")
        } catch {
            state = .failed(L("Controllo non riuscito: %@", error.localizedDescription))
            diag(.update, "check failed: \(error.localizedDescription)")
        }
    }

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        diag(.update, "update command copied")
    }

    /// Apre il Terminale ed esegue il comando.
    func runInTerminal() {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            terminalError = L("Il Terminale non ha eseguito il comando: copialo e incollalo tu. (%@)",
                              (error[NSAppleScript.errorMessage] as? String) ?? "?")
            diag(.update, "run in Terminal failed: \(error)")
        } else {
            terminalError = nil
            diag(.update, "update command sent to Terminal")
        }
    }
}
