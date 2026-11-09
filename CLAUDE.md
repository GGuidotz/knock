# Knock

App macOS per la barra dei menu (Swift/SwiftUI, macOS 14+): tap sul tavolo accanto al Mac come 8 interruttori
(4 zone x doppio/triplo). Stesso schema di GGuidotz/whats-going-on e GGuidotz/nod.

- Compilazione: `./build.sh` (swiftc diretto, niente progetto Xcode). Firma con l'identità locale di Nod
  (~/.nod-signing) se c'è, altrimenti ad hoc: serve perché macOS ricordi il permesso del microfono. In locale Swift
  compila: compila sempre prima di consegnare (nella sandbox di Claude Code servono i permessi fuori sandbox per le
  macro di SwiftUI e per IOKit).
- `Sources/Core` non importa SwiftUI né AppKit (Foundation, Accelerate, AVFAudio, IOKit sì).
- Motore: `TapEngine` (AVAudioEngine + `MotionSensor`) -> `TapDetector` (colpi = salto di energia 8x sopra gli ultimi
  50 ms, gruppi entro 450 ms) -> `ZoneClassifier` (kNN standardizzato, calibrazione in Application Support).
  Mai salvare suono. Il sensore di movimento (AppleSPU HID, pagina 0xFF00, uso 3/9) non è documentato: sempre opzionale.
- Testi: chiave = frase italiana, `L("…")`; ogni chiave nuova va in `Localization/en.lproj/Localizable.strings`.
  Controllo: `python3 -I tools/check-strings.py`.
- Versione: `VERSION` + sezione `## <versione> · <data>` in cima a `CHANGELOG.md` e `CHANGELOG.en.md`.
- Design: Human Interface Guidelines; colore mai unico segnale; vetro solo sui controlli che galleggiano, dietro
  `if #available(macOS 26, *)` (`Sources/Island/Style.swift`). Interfaccia in italiano e inglese, niente emoji.
- Leggerezza: sotto l'1% di CPU in ascolto; in pausa, senza calibrazione o con il Mac in stop niente microfono né sensori.
- Prove guidate: meglio sessioni passo per passo (mappa del tavolo, "tocca 2 volte qui") a istruzioni lunghe.
- Repo pubblico: mai dati personali in codice, commenti, commit.
