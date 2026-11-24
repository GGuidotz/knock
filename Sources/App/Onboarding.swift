// La guida al primo avvio: tre schermate brevi. Cosa fa Knock, il permesso del microfono (chiesto qui, spiegando
// perché), poi la calibrazione. Si può chiudere in qualunque momento e riaprire da Impostazioni › Generale.

import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 500, height: 440)

    var body: some View {
        VStack(spacing: 18) {
            Group {
                switch page {
                case 0: welcome
                case 1: microphone
                default: calibrate
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(reduceMotion ? .opacity : .sgBlurReplace)
            .id(page)
            HStack {
                if page > 0 {
                    Button(L("Indietro")) { go(page - 1) }
                        .buttonStyle(SGCapsuleButtonStyle(.secondary, size: .large))
                }
                Spacer()
                PageDots(page: page, count: 3)
                Spacer()
                primaryButton
            }
        }
        .padding(28)
        .padding(.top, 14)
        .frame(width: Self.size.width, height: Self.size.height)
        .sguardoAccent(default: .knock)
    }

    private func go(_ next: Int) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : SG.Motion.standard) { page = min(max(0, next), 2) }
    }

    @ViewBuilder private var primaryButton: some View {
        switch page {
        case 0:
            Button(L("Continua")) { go(1) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SGCapsuleButtonStyle(.primary, size: .large))
        case 1:
            if model.micPermission == .authorized {
                Button(L("Continua")) { go(2) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(SGCapsuleButtonStyle(.primary, size: .large))
            } else {
                Button(L("Controlla i permessi")) {
                    model.prefs.onboardingDone = true
                    close()
                    model.showPermissions()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SGCapsuleButtonStyle(.primary, size: .large))
            }
        default:
            Button(L("Calibra ora")) { finish(); model.showCalibration() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SGCapsuleButtonStyle(.primary, size: .large))
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "hand.tap").font(.system(size: 44, weight: .light)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(L("Benvenuto in Knock")).font(SG.Font.title)
                .accessibilityAddTraits(.isHeader)
            Text(L("Il tavolo accanto al Mac diventa un pannello di interruttori: tocca due o tre volte in uno dei quattro angoli, e Knock capisce dove e quante volte. Fanno 8 interruttori."))
                .font(SG.Font.instruction).foregroundStyle(SG.Ink.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            TableMap(highlight: nil).scaleEffect(0.8)
        }
    }

    private var microphone: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic").font(.system(size: 40, weight: .light)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(L("Il microfono")).font(SG.Font.title)
                .accessibilityAddTraits(.isHeader)
            Text(L("Knock sente i tap con il microfono e, sui Mac che ce l'hanno, con il sensore di movimento. Il suono resta in memoria per meno di due secondi: non viene mai registrato, salvato o inviato."))
                .font(SG.Font.instruction).foregroundStyle(SG.Ink.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(L("Mentre Knock ascolta, macOS mostra il pallino arancione nella barra dei menu. Puoi mettere in pausa quando vuoi."))
                .font(SG.Font.body).foregroundStyle(SG.Ink.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if (model.micPermission == .denied || model.micPermission == .restricted) {
                Button(L("Apri Impostazioni › Microfono")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
                .buttonStyle(.sgSecondary)
            } else if model.micPermission == .authorized {
                Label(L("Permesso concesso"), systemImage: "checkmark.circle.fill")
                    .font(SG.Font.body).foregroundStyle(Palette.calm)
            }
        }
    }

    private var calibrate: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2").font(.system(size: 40, weight: .light)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(L("La calibrazione")).font(SG.Font.title)
                .accessibilityAddTraits(.isHeader)
            Text(L("Ogni tavolo suona in modo diverso: Knock impara il tuo con 24 gruppi di tap guidati, circa un minuto e mezzo. Poi vive nella barra dei menu, con la griglia che si accende sulla zona che hai toccato."))
                .font(SG.Font.instruction).foregroundStyle(SG.Ink.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(L("Più tardi")) { finish() }.buttonStyle(.sgSecondary)
        }
    }

    private func finish() {
        model.prefs.onboardingDone = true
        close()
    }
}

/// I tre puntini della guida: quello della pagina in corso ha il colore d'accento.
private struct PageDots: View {
    let page: Int
    let count: Int
    @Environment(\.sgAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(i == page ? accent.base : SG.Ink.tertiary.opacity(0.5)).frame(width: 7, height: 7)
            }
        }
        .animation(SG.Motion.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Pagina %d di %d", page + 1, count))
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let w = TranslucentWindow.make(OnboardingView(model: model, close: { [weak self] in self?.window?.close() }),
                                           size: OnboardingView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Benvenuto in Knock")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                AppModel.shared.prefs.onboardingDone = true
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
    }
}
