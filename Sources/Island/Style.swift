// Colori e vetro, in un posto solo. Le forme, i riempimenti e le molle vengono da Sguardo, il sistema di design comune
// (github.com/GGuidotz/sguardo, submodule in Vendor/Sguardo, compilato insieme all'app da build.sh): qui restano i
// colori di Knock.
// Regola (HIG, Liquid Glass): il vetro solo sui controlli che galleggiano (la barra delle schede, le barre in fondo);
// il contenuto usa i riempimenti di Sguardo (velo traslucido + filo da 1 pt). Prima di macOS 26 il vetro diventa un
// materiale con velo e filo (Sguardo). Riduci trasparenza e Aumenta contrasto li gestisce il sistema.

import AppKit
import SwiftUI

enum Palette {
    /// I colori del marchio: verde calmo per le conferme, rosso per gli errori. Il verde calmo (#33C773) è anche
    /// l'accento predefinito dell'app: `SG.Accent.knock` in Sguardo (si cambia da Impostazioni › Generale).
    static let calm = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let alarm = Color(red: 0.93, green: 0.26, blue: 0.27)
    static let brand = LinearGradient(colors: [calm, Color(red: 0.98, green: 0.78, blue: 0.25), alarm],
                                      startPoint: .leading, endPoint: .trailing)
}

extension View {
    /// Vetro per i controlli che galleggiano. Mai per il contenuto. Prima di macOS 26: materiale + velo + filo (Sguardo).
    func glassSurface(in shape: some InsettableShape, interactive: Bool = false) -> some View {
        sgFloatingChrome(in: shape, interactive: interactive)
    }

    /// Pulsante di vetro (secondario), solo nelle barre che galleggiano. Nel contenuto: `.buttonStyle(.sgSecondary)`.
    @ViewBuilder
    func floatingGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Il pulsante principale di una barra che galleggia: vetro colorato. Nel contenuto: `.buttonStyle(.sgPrimary)`.
    @ViewBuilder
    func floatingGlassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Una scheda del contenuto, come le righe di Sguardo: velo traslucido (più bianco della finestra in chiaro), filo da
    /// 1 pt, angoli continui da 16 pt. Niente vetro (il vetro è dei controlli), niente ombre, niente animazioni.
    func contentCard(padding: CGFloat = 12, radius: CGFloat = SG.Radius.row) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ContentCardBackground(radius: radius))
    }
}

private struct ContentCardBackground: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .sgRowSurface(in: shape)
            .overlay {
                // Aumenta contrasto: un bordo pieno sopra il filo.
                if contrast == .increased { shape.strokeBorder(Color.primary.opacity(0.35), lineWidth: 1) }
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
