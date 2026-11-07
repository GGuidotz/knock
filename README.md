# Knock

Il tavolo accanto al Mac diventa un pannello di interruttori. [English](README.en.md)

Tocca due o tre volte il tavolo in uno dei quattro angoli intorno al MacBook: Knock capisce **dove** (in alto o in
basso, a sinistra o a destra) e **quante volte**. Fanno 8 interruttori in più, senza nessun accessorio. Vive nella barra
dei menu come una piccola griglia 2x2: il quadrato della zona toccata si accende per un attimo, con accanto il numero
di tap.

In questa prima versione gli interruttori si vedono e basta. Collegarli ad azioni (approvare o rifiutare in un'app,
avanti e indietro tra le slide, togliere il microfono, aprire un'app) arriva nelle prossime.

## Come funziona

Il microfono del Mac arriva a macOS come un canale solo, quindi non si può "triangolare" il colpo. Si sfrutta invece la
firma di ogni punto del tavolo: il colpo arriva al Mac per l'aria e attraverso il tavolo, e il suono (spettro,
decadimento) e la vibrazione cambiano con il punto. Sui MacBook con Apple Silicon (M2 e successivi) Knock legge anche
l'accelerometro e il giroscopio interni, che distinguono meglio sinistra e destra.

- **Rilevamento.** Un colpo è un salto netto di energia sopra il rumore di fondo; la coda che si spegne non conta come
  colpo nuovo. Colpi a meno di 450 ms formano un gruppo: 2 = doppio, 3 = triplo.
- **Zona.** Una calibrazione guidata (24 gruppi, circa un minuto e mezzo) raccoglie esempi per ogni zona; poi un
  classificatore a vicini più prossimi riconosce la zona e scarta i gruppi che non somigliano a nulla.
- **Niente falsi allarmi mentre scrivi.** Fino a un secondo dopo l'ultimo tasto o movimento del trackpad i tap non
  contano.

Prova di fattibilità su un MacBook Air M2 13" (64 gruppi guidati, cartella `tools/`): doppio o triplo riconosciuto
nell'89% dei casi, zona nel 96% (100% alto/basso). Numeri misurati con calibrazione e prova nella stessa sessione:
in uso reale servono un tavolo e una posizione del Mac stabili, e una nuova calibrazione quando cambiano.

## Privacy

Il suono resta in memoria per meno di due secondi e non viene mai registrato, salvato o inviato. La calibrazione
salva solo numeri (le caratteristiche dei tap) in `~/Library/Application Support/Knock/`. Mentre Knock ascolta, macOS
mostra il pallino arancione del microfono: è normale. In pausa non usa né microfono né sensori.

## Installazione

```sh
brew install --cask gguidotz/tap/knock
```

Homebrew scarica il DMG dalla release, copia l'app in Applicazioni e toglie la quarantena (l'app non è notarizzata).
Al primo avvio una guida breve chiede il permesso del microfono e porta alla calibrazione.
Aggiornare: `brew update && brew upgrade --cask knock`.

Dai sorgenti (serve Xcode o gli strumenti a riga di comando):

```sh
git clone https://github.com/GGuidotz/knock.git ~/Developer/knock
cd ~/Developer/knock && ./build.sh --install
```

Requisiti: macOS 14 o successivo. Il sensore di movimento c'è sui MacBook con chip M2 e successivi; senza, Knock usa
solo il microfono.

## Sviluppo

- `./build.sh` compila `build/Knock.app` (universale), `--install` la mette in Applicazioni, `--dmg` crea il DMG.
- `./release.sh` pubblica la versione: release GitHub con il DMG e cask aggiornato nel tap.
- `tools/imuprobe`, `tools/tapprobe`: gli strumenti della prova di fattibilità (lettura del sensore, sessione guidata
  che salva le caratteristiche in CSV, `analyze.py` per l'accuratezza).
- `python3 -I tools/check-strings.py`: controlla le traduzioni.

Il sensore di movimento è letto tramite il coprocessore dei sensori (AppleSPU) come dispositivo HID: non è un'API
documentata da Apple e potrebbe cambiare con un aggiornamento di macOS.

## Licenza

MIT. Feedback e idee: [Issues](https://github.com/GGuidotz/knock/issues), oppure da Impostazioni › Feedback.
