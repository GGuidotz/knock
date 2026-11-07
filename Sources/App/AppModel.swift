// Knock: tap sul tavolo accanto al Mac come interruttori. Vive nella barra dei menu (LSUIElement: niente Dock).
// AppModel tiene insieme motore, calibrazioni, azioni, preferenze, aggiornamenti e finestre.

import AVFoundation
import AppKit
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let prefs: Preferences
    let engine = TapEngine()
    let updater: Updater

    /// Le calibrazioni, una per modalità di ascolto.
    @Published private(set) var classifiers: [ListeningMode: ZoneClassifier] = [:]
    /// Gli ultimi interruttori riconosciuti, dal più recente.
    @Published private(set) var events: [TapEvent] = []
    @Published private(set) var engineState = TapEngine.State.stopped
    @Published private(set) var micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
    /// Il microfono di sistema è muto (azione o rilevato all'avvio): Knock ascolta con i soli sensori.
    @Published var systemMicMuted = SystemMicrophone.isMuted { didSet { apply() } }
    @Published var settingsTab: SettingsTab = .general
    /// Chiamato a ogni evento: la voce nella barra lampeggia.
    var onEvent: ((TapEvent) -> Void)?
    /// La calibrazione aperta riceve i gruppi da qui.
    var calibrationSink: ((TapPattern) -> Void)?

    private let settingsWindow = SettingsWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private let whatsNewWindow = WhatsNewWindowController()
    private let calibrationWindow = CalibrationWindowController()
    private let permissionsWindow = PermissionsWindowController()
    private var bag = Set<AnyCancellable>()

    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// La modalità in cui Knock ascolterebbe adesso (tiene conto del microfono sospeso e dei Mac senza sensore).
    var effectiveMode: ListeningMode { engine.effectiveMode }
    var classifier: ZoneClassifier? { classifiers[effectiveMode] }
    var isCalibrated: Bool { classifier != nil }
    var micSuspended: Bool { prefs.knockMicOff || systemMicMuted }

    private init() {
        let prefs = Preferences()
        self.prefs = prefs
        updater = Updater(prefs: prefs)
        classifiers = CalibrationStore.load()
        engine.classifiers = classifiers
        engine.onEvent = { [weak self] e in MainActor.assumeIsolated { self?.received(e) } }
        engine.onPattern = { [weak self] p in MainActor.assumeIsolated { self?.calibrationSink?(p) } }
        apply()
        prefs.objectWillChange
            .sink { [unowned self] _ in Task { @MainActor in self.apply() } }
            .store(in: &bag)
        // Mac in stop: niente ascolto. Si riprende al risveglio.
        let ws = NSWorkspace.shared.notificationCenter
        ws.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [unowned self] _ in MainActor.assumeIsolated { self.stopEngine() } }.store(in: &bag)
        ws.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [unowned self] _ in MainActor.assumeIsolated { self.apply() } }.store(in: &bag)
    }

    func didLaunch() {
        diag(.app, "launched \(appVersion), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        diag(.engine, "motion sensor available: \(MotionSensor.isAvailable), system mic muted: \(systemMicMuted)")
        updater.start()
    }

    // MARK: - Motore

    /// Ascolta solo se: non sei in pausa, c'è una calibrazione per la modalità (o la calibrazione è aperta), e c'è
    /// il permesso del microfono quando la modalità lo usa.
    private func apply() {
        engine.sensitivity = prefs.sensitivity
        engine.typingGuard = prefs.ignoreWhileTyping ? 1.0 : 0
        engine.mode = prefs.mode
        engine.micSuspended = micSuspended
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        let mode = engine.effectiveMode
        let micOK = !mode.usesMic || micPermission == .authorized
        let wanted = micOK && (calibrationSink != nil || (prefs.listening && isCalibrated))
        if wanted && engine.state == .running && engine.activeMode != mode {
            stopEngine()   // cambia modalità: si riparte con il rilevatore giusto
        }
        if wanted && engine.state != .running {
            engine.start()
            diag(.engine, "start \(mode.rawValue): \(engine.state), input \(engine.inputDescription), motion \(engine.motion.isRunning)")
        } else if !wanted && engine.state == .running {
            stopEngine()
        }
        engineState = engine.state
    }

    private func stopEngine() {
        engine.stop()
        engineState = engine.state
        diag(.engine, "stop")
    }

    func refresh() { apply() }

    func requestMicrophone(then done: @escaping @MainActor (Bool) -> Void) {
        NSApp.activate()   // l'avviso di sistema compare davanti solo se l'app è attiva
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.apply()
                    diag(.engine, "microphone permission: \(ok)")
                    done(ok)
                }
            }
        }
    }

    func togglePause() { prefs.listening.toggle() }

    /// "Spegni tutti i sensori": niente resta in ascolto; si riaccende dal menu.
    func stopAllSensors() { prefs.listening = false }

    /// "Spegni o riaccendi il microfono di Knock": spento, si ascolta con i soli sensori.
    func toggleKnockMic() { prefs.knockMicOff.toggle() }

    private func received(_ e: TapEvent) {
        var e = e
        if let s = e.tapSwitch {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let (action, profile) = ActionProfiles.resolve(s, frontmost: front, in: prefs.profiles)
            if action != .none {
                e.actionTitle = action.title + (profile.map { $0.isGlobal ? "" : " (\($0.name))" } ?? "")
                if let error = ActionRunner.run(action, model: self) { e.actionTitle = error }
            }
        }
        if prefs.sound { NSSound(named: "Tink")?.play() }
        events.insert(e, at: 0)
        if events.count > 30 { events.removeLast(events.count - 30) }
        onEvent?(e)
    }

    /// Tutti i profili insieme usano tasti: serve Accessibilità.
    var actionsNeedAccessibility: Bool {
        prefs.profiles.contains { p in p.actions.values.contains(where: \.needsAccessibility) }
    }

    // MARK: - Calibrazione

    func beginCalibration(sink: @escaping (TapPattern) -> Void) {
        calibrationSink = sink
        engine.calibrating = true
        apply()
    }

    func endCalibration(result: [ListeningMode: ZoneClassifier]?) {
        calibrationSink = nil
        engine.calibrating = false
        if let result, !result.isEmpty {
            classifiers.merge(result) { _, new in new }
            engine.classifiers = classifiers
            try? CalibrationStore.save(classifiers)
            let summary = result.map { "\($0.key.rawValue) \(Int($0.value.accuracy * 100))%" }.sorted().joined(separator: ", ")
            diag(.engine, "calibrated: \(summary)")
        }
        apply()
    }

    func forgetCalibration() {
        CalibrationStore.delete()
        classifiers = [:]
        engine.classifiers = [:]
        apply()
    }

    // MARK: - Finestre

    func showSettings(_ tab: SettingsTab?) {
        if let tab { settingsTab = tab }
        settingsWindow.show(model: self)
    }

    func showOnboarding() { onboardingWindow.show(model: self) }
    func showCalibration() { calibrationWindow.show(model: self) }
    func showPermissions() { permissionsWindow.show(model: self) }
    func showWhatsNewIfUpdated(firstLaunch: Bool) { whatsNewWindow.showIfUpdated(firstLaunch: firstLaunch) }
    func showWhatsNew() { whatsNewWindow.showCurrent() }
}

/// Confronto numerico tra versioni ("0.10.0" > "0.9.2").
struct Version: Comparable {
    let parts: [Int]
    init(_ string: String) { parts = string.split(separator: ".").map { Int($0) ?? 0 } }

    static func < (a: Version, b: Version) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }
}
