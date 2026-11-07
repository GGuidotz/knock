// Esegue le azioni degli interruttori.
//  - Tasti: CGEvent mandati all'app in primo piano (serve Accessibilità; se manca, si apre la pagina Permessi).
//  - App e indirizzi: NSWorkspace. Comandi Rapidi: /usr/bin/shortcuts run "<nome>".
//  - Muto di sistema: CoreAudio sul microfono predefinito (proprietà Mute; se il dispositivo non la ha, volume a 0 e
//    poi di nuovo al valore di prima). Nessun permesso.
// Ogni azione eseguita va nel registro (solo il tipo, mai i contenuti).

import AppKit
import ApplicationServices
import CoreAudio
import Foundation

@MainActor
enum ActionRunner {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Mostra la richiesta di sistema per Accessibilità (una volta; poi si attiva in Impostazioni di Sistema).
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Esegue l'azione. Restituisce un messaggio se non è andata.
    @discardableResult
    static func run(_ action: TapAction, model: AppModel) -> String? {
        diag(.actions, "run \(action.kind.rawValue)")
        switch action {
        case .none:
            return nil
        case .key(let k):
            guard hasAccessibility else {
                model.showPermissions()
                return L("Per mandare tasti serve il permesso Accessibilità.")
            }
            sendKey(k)
            return nil
        case .openApp(let bundleID, _):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return L("App non trovata.")
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return nil
        case .shortcut(let name):
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["run", name]
            do { try p.run() } catch { return error.localizedDescription }
            return nil
        case .openURL(let s):
            guard let url = URL(string: s), url.scheme != nil else { return L("Indirizzo non valido.") }
            NSWorkspace.shared.open(url)
            return nil
        case .toggleSystemMute:
            guard let muted = SystemMicrophone.toggleMute() else { return L("Non riesco a cambiare il muto del microfono.") }
            model.systemMicMuted = muted
            return nil
        case .toggleKnockMic:
            model.toggleKnockMic()
            return nil
        case .stopListening:
            model.stopAllSensors()
            return nil
        }
    }

    private static func sendKey(_ k: KeyCombo) {
        let src = CGEventSource(stateID: .hidSystemState)
        var flags = CGEventFlags()
        let m = NSEvent.ModifierFlags(rawValue: k.modifiers)
        if m.contains(.command) { flags.insert(.maskCommand) }
        if m.contains(.option) { flags.insert(.maskAlternate) }
        if m.contains(.control) { flags.insert(.maskControl) }
        if m.contains(.shift) { flags.insert(.maskShift) }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: k.keyCode, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }
}

/// Il microfono di sistema (dispositivo di ingresso predefinito).
enum SystemMicrophone {
    private static var savedVolume: Float32?

    private static var defaultInput: AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// È muto adesso (proprietà Mute, oppure volume a zero).
    static var isMuted: Bool {
        guard let dev = defaultInput else { return false }
        var addr = address(kAudioDevicePropertyMute)
        if AudioObjectHasProperty(dev, &addr) {
            var v: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr { return v != 0 }
        }
        return volume(dev) == 0
    }

    /// Cambia il muto; restituisce il nuovo stato, o nil se il dispositivo non lo permette.
    static func toggleMute() -> Bool? {
        guard let dev = defaultInput else { return nil }
        let target = !isMuted
        var addr = address(kAudioDevicePropertyMute)
        var settable = DarwinBoolean(false)
        if AudioObjectHasProperty(dev, &addr), AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue {
            var v: UInt32 = target ? 1 : 0
            if AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr { return target }
        }
        // Senza Mute: volume d'ingresso a zero e poi di nuovo com'era.
        if target {
            savedVolume = volume(dev) ?? 0.75
            return setVolume(dev, 0) ? true : nil
        } else {
            return setVolume(dev, savedVolume ?? 0.75) ? false : nil
        }
    }

    private static func volume(_ dev: AudioObjectID) -> Float32? {
        var addr = address(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(dev, &addr) else { return nil }
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func setVolume(_ dev: AudioObjectID, _ v: Float32) -> Bool {
        var addr = address(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(dev, &addr) else { return false }
        var value = v
        return AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
}
