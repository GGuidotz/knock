// Knock: tap sul tavolo accanto al Mac come interruttori. Vive nella barra dei menu (LSUIElement: niente Dock).
// AppModel tiene insieme motore, calibrazione, preferenze, aggiornamenti e finestre.
// Versione 0.1: gli 8 interruttori esistono e si vedono (barra, registro); le azioni collegate arriveranno dopo.

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

    @Published private(set) var classifier: ZoneClassifier?
    /// Gli ultimi interruttori riconosciuti, dal più recente.
    @Published private(set) var events: [TapEvent] = []
    @Published private(set) var engineState = TapEngine.State.stopped
    @Published private(set) var micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
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
    var isCalibrated: Bool { classifier != nil }

    private init() {
        let prefs = Preferences()
        self.prefs = prefs
        updater = Updater(prefs: prefs)
        classifier = CalibrationStore.load()
        engine.classifier = classifier
        engine.onEvent = { [weak self] e in MainActor.assumeIsolated { self?.received(e) } }
        engine.onPattern = { [weak self] p in MainActor.assumeIsolated { self?.calibrationSink?(p) } }
        apply()
        prefs.objectWillChange
            .sink { [unowned self] _ in Task { @MainActor in self.apply() } }
            .store(in: &bag)
        // Mac in stop o schermo bloccato: niente ascolto. Si riprende al risveglio.
        let ws = NSWorkspace.shared.notificationCenter
        ws.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [unowned self] _ in MainActor.assumeIsolated { self.stopEngine() } }.store(in: &bag)
        ws.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [unowned self] _ in MainActor.assumeIsolated { self.apply() } }.store(in: &bag)
    }

    func didLaunch() {
        diag(.app, "launched \(appVersion), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        diag(.engine, "motion sensor available: \(MotionSensor.isAvailable)")
        updater.start()
    }

    // MARK: - Motore

    /// Ascolta solo se: c'è il permesso, non sei in pausa, e c'è una calibrazione (o la calibrazione è aperta).
    private func apply() {
        engine.sensitivity = prefs.sensitivity
        engine.typingGuard = prefs.ignoreWhileTyping ? 1.0 : 0
        if engine.useMotion != prefs.useMotion {
            engine.useMotion = prefs.useMotion
            if engine.state == .running { stopEngine() }
        }
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        let wanted = micPermission == .authorized && (calibrationSink != nil || (prefs.listening && isCalibrated))
        if wanted && engine.state != .running {
            engine.start()
            diag(.engine, "start: \(engine.state), input \(engine.inputDescription), motion \(engine.motion.isRunning)")
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

    func togglePause() {
        prefs.listening.toggle()
    }

    private func received(_ e: TapEvent) {
        events.insert(e, at: 0)
        if events.count > 30 { events.removeLast(events.count - 30) }
        onEvent?(e)
    }

    // MARK: - Calibrazione

    func beginCalibration(sink: @escaping (TapPattern) -> Void) {
        calibrationSink = sink
        engine.calibrating = true
        apply()
    }

    func endCalibration(result: ZoneClassifier?) {
        calibrationSink = nil
        engine.calibrating = false
        if let result {
            classifier = result
            engine.classifier = result
            try? CalibrationStore.save(result)
            diag(.engine, "calibrated: \(result.samples.count) samples, accuracy \(Int(result.accuracy * 100))%, motion \(result.usesMotion)")
        }
        apply()
    }

    func forgetCalibration() {
        CalibrationStore.delete()
        classifier = nil
        engine.classifier = nil
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
