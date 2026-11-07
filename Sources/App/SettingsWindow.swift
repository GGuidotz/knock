// La finestra delle impostazioni: una finestra AppKit con dentro SwiftUI, perché senza il ciclo di vita di SwiftUI
// la scena Settings non c'è. Barra del titolo trasparente: la barra delle schede di vetro galleggia sopra il contenuto.
// Il fondo della finestra è un materiale traslucido (quello delle barre laterali): lascia passare i colori della
// scrivania, resta leggibile, e con Riduci trasparenza diventa pieno da solo. Lo disegna il sistema, non costa CPU.

import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, switches, actions, updates, feedback
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("Generale")
        case .switches: L("Interruttori")
        case .actions: L("Azioni")
        case .updates: L("Aggiornamenti")
        case .feedback: L("Feedback")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .switches: "square.grid.2x2"
        case .actions: "bolt"
        case .updates: "arrow.down.circle"
        case .feedback: "bubble.left.and.text.bubble.right"
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let w = TranslucentWindow.make(SettingsView(model: model), size: SettingsView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Impostazioni di Knock")   // per Mission Control e VoiceOver, anche dopo un cambio di lingua
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Finestra chiusa: via anche le sue viste, che altrimenti continuerebbero a ridisegnare l'anteprima a ogni lettura.
    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
    }
}

/// Una finestra con il fondo traslucido del sistema (materiale delle barre laterali) e la barra del titolo trasparente:
/// impostazioni, guida iniziale e attrezzi (che si possono ridimensionare).
@MainActor
enum TranslucentWindow {
    static func make(_ root: some View, size: CGSize, resizable: Bool = false) -> NSWindow {
        let host = NSHostingController(rootView: root)
        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        let container = NSViewController()
        container.view = effect
        container.addChild(host)
        effect.frame = NSRect(origin: .zero, size: size)
        host.view.frame = effect.bounds
        host.view.autoresizingMask = [.width, .height]
        effect.addSubview(host.view)
        let w = NSWindow(contentViewController: container)
        w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { w.styleMask.insert(.resizable) }
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.setContentSize(size)
        w.center()
        return w
    }
}

/// La barra delle schede: un controllo che galleggia, quindi di vetro. ⌘1…⌘5 per passare da una scheda all'altra.
struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                    let selected = selection == tab
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .frame(height: 18)
                            Text(tab.title)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: 92, height: 44)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(5)
            .glassSurface(in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
    }
}
