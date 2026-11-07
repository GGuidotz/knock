// Colori e vetro, in un posto solo.
// Regola (HIG, Liquid Glass): il vetro solo sui controlli che galleggiano (la barra delle schede, i pulsanti in fondo
// al pannello); il contenuto usa riempimenti standard. Il pannello stesso è un popover: su macOS 26 il vetro ce lo mette
// il sistema. Prima di macOS 26 il vetro diventa un materiale sottile. Riduci trasparenza e Aumenta contrasto li
// gestisce il sistema.

import AppKit
import SwiftUI

enum Palette {
    /// I colori del marchio: verde calmo per le conferme, rosso per gli errori.
    static let calm = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let alarm = Color(red: 0.93, green: 0.26, blue: 0.27)
    static let brand = LinearGradient(colors: [calm, Color(red: 0.98, green: 0.78, blue: 0.25), alarm],
                                      startPoint: .leading, endPoint: .trailing)
}

extension View {
    /// Vetro per i controlli che galleggiano. Mai per il contenuto.
    @ViewBuilder
    func glassSurface(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Pulsante di vetro (secondario).
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Il pulsante principale, uno per vista: vetro colorato.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Una scheda del contenuto: non è vetro (il vetro è dei controlli), ma ci somiglia: un velo chiaro su cui passa il
    /// vetro del pannello e un filo di luce sul bordo alto. Tutto statico: niente sfocature in più, niente animazioni.
    func contentCard(padding: CGFloat = 12, radius: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ContentCardBackground(radius: radius))
    }
}

private struct ContentCardBackground: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark
        let strong = contrast == .increased
        content
            .background(dark ? Color.white.opacity(strong ? 0.12 : 0.07) : Color.white.opacity(strong ? 0.8 : 0.5), in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(dark ? 0.22 : 0.9), Color.white.opacity(dark ? 0.04 : 0.3)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            }
            .overlay {
                if strong { shape.strokeBorder(Color.primary.opacity(0.25), lineWidth: 1) }
            }
    }
}

extension View {
    /// Su macOS 26 la barra in basso diventa una barra di vetro con l'effetto bordo: il contenuto ci scorre sotto e
    /// sfuma. Prima di macOS 26, un normale riquadro in fondo.
    @ViewBuilder
    func floatingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(macOS 26.0, *) {
            self.safeAreaBar(edge: .bottom, spacing: 0, content: bar)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) { bar().background(.bar) }
        }
    }
}

/// Contenitore dei controlli di vetro: su macOS 26 le forme vicine si fondono e si trasformano insieme.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
