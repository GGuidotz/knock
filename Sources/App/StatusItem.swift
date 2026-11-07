// La voce nella barra dei menu: una griglia 2x2 come il tavolo intorno al Mac. Quando un interruttore scatta, il
// quadrato della zona si riempie per un secondo e mezzo con accanto il numero di tap (2 o 3). In pausa la griglia è
// tenue; senza calibrazione è vuota con un punto interrogativo. Clic: un menu breve, ricostruito a ogni apertura.

import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var bag = Set<AnyCancellable>()
    private var flash: TapEvent?
    private var flashTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        super.init()
        item.autosaveName = "Knock"
        menu.delegate = self
        item.menu = menu
        model.onEvent = { [weak self] e in self?.show(e) }
        model.prefs.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }.store(in: &bag)
        model.$engineState.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }.store(in: &bag)
        model.$classifier.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }.store(in: &bag)
        redraw()
    }

    private func show(_ e: TapEvent) {
        guard model.prefs.flashMenuBar else { return }
        flash = e
        redraw()
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.flash = nil
            self?.redraw()
        }
    }

    private func redraw() {
        guard let button = item.button else { return }
        let state: GridIcon.State
        if let flash {
            state = .event(flash.zone, flash.taps)
        } else if !model.isCalibrated {
            state = .uncalibrated
        } else if model.engineState == .running {
            state = .listening
        } else {
            state = .paused
        }
        button.image = GridIcon.image(state)
        let text = statusText
        button.toolTip = "Knock: " + text
        button.setAccessibilityLabel("Knock: " + text)
    }

    private var statusText: String {
        if model.micPermission == .denied || model.micPermission == .restricted {
            return L("serve il permesso del microfono")
        }
        if !model.isCalibrated { return L("da calibrare") }
        switch model.engineState {
        case .running: return L("in ascolto")
        case .failed(let why): return L("non riesco ad ascoltare: %@", why)
        case .stopped: return L("in pausa")
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: L("Knock è %@", statusText), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if let last = model.events.first {
            let line = NSMenuItem(title: L("Ultimo: %@", Self.describe(last)), action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }
        menu.addItem(.separator())

        if model.isCalibrated {
            let pause = model.prefs.listening ? L("Metti in pausa") : L("Riprendi l'ascolto")
            menu.addItem(withTitle: pause, action: #selector(togglePause), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: model.isCalibrated ? L("Ricalibra…") : L("Calibra…"),
                     action: #selector(calibrate), keyEquivalent: "").target = self
        if !model.events.isEmpty {
            let recent = NSMenu()
            for e in model.events.prefix(12) {
                let it = NSMenuItem(title: Self.describe(e), action: nil, keyEquivalent: "")
                it.isEnabled = false
                recent.addItem(it)
            }
            let sub = NSMenuItem(title: L("Ultimi tap"), action: nil, keyEquivalent: "")
            sub.submenu = recent
            menu.addItem(sub)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Impostazioni…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L("Novità e aggiornamenti…"), action: #selector(openUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Invia un feedback…"), action: #selector(openFeedback), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Esci da Knock"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// "Doppio tap, in alto a destra · 14:02:31" oppure "Triplo tap, zona non riconosciuta".
    static func describe(_ e: TapEvent) -> String {
        let time = e.date.formatted(date: .omitted, time: .standard)
        let count = TapCount(rawValue: e.taps)?.title ?? L("%d tap", e.taps)
        let zone = e.zone?.title.lowercased() ?? L("zona non riconosciuta")
        return "\(count), \(zone) · \(time)"
    }

    @objc private func togglePause() { model.togglePause() }
    @objc private func calibrate() { model.showCalibration() }
    @objc private func openSettings() { model.showSettings(.general) }
    @objc private func openUpdates() { model.showSettings(.updates) }
    @objc private func openFeedback() { model.showSettings(.feedback) }
}

/// L'icona: quattro quadratini come le quattro zone, disegnati a mano (immagine modello, quindi del colore della barra).
enum GridIcon {
    enum State: Equatable {
        case listening, paused, uncalibrated
        case event(Zone?, Int)
    }

    static func image(_ state: State) -> NSImage {
        let cell: CGFloat = 6, gap: CGFloat = 2
        let grid = cell * 2 + gap
        var width = grid
        var label: NSAttributedString?
        if case .event(_, let taps) = state {
            label = NSAttributedString(string: "\(taps)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.black,
            ])
            width += 3 + (label?.size().width ?? 0)
        }
        if state == .uncalibrated {
            label = NSAttributedString(string: "?", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.black,
            ])
            width += 2 + (label?.size().width ?? 0)
        }
        let size = NSSize(width: ceil(width), height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            let y0 = (16 - grid) / 2
            let alpha: CGFloat = state == .paused ? 0.4 : 1
            NSColor.black.withAlphaComponent(alpha).set()
            for zone in Zone.allCases {
                let x = zone.isLeft ? 0 : cell + gap
                let y = zone.isTop ? y0 + cell + gap : y0
                let r = NSBezierPath(roundedRect: NSRect(x: x + 0.5, y: y + 0.5, width: cell - 1, height: cell - 1),
                                     xRadius: 1.5, yRadius: 1.5)
                let filled: Bool
                switch state {
                case .listening, .paused: filled = false
                case .uncalibrated: filled = false
                case .event(let z, _): filled = z == zone
                }
                if filled { r.fill() } else { r.lineWidth = 1; r.stroke() }
            }
            if let label {
                let s = label.size()
                label.draw(at: NSPoint(x: grid + 2.5, y: (16 - s.height) / 2))
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
