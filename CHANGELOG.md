# Novità di Knock

## 0.2.0 · 2026-11-07
Prima versione pubblica: gli 8 interruttori fanno qualcosa, e Knock può ascoltare anche senza microfono.

### Novità
- **Azioni sugli interruttori.** Ogni doppio o triplo tap può premere un tasto, aprire un'app o un indirizzo, eseguire un Comando Rapido, mettere il muto al microfono di sistema, spegnere il microfono di Knock o tutti i sensori.
- **Profili per app.** Le azioni possono cambiare con l'app in primo piano: pronti quelli per Claude e il Terminale (doppio a destra approva, doppio a sinistra rifiuta) e per Keynote e PowerPoint (slide avanti e indietro), più "Sempre" per tutte le altre.
- **Solo sensori (sperimentale).** Sui MacBook con Apple Silicon (M2 e successivi) Knock può ascoltare con il solo sensore di movimento: niente microfono e niente pallino arancione. Quando spegni il microfono di Knock o metti il muto di sistema ci passa da solo, così un tap può riaccenderlo.
- **Spegni tutti i sensori.** Un interruttore che spegne microfono e sensori per risparmiare batteria; si riaccende dal menu.
- **Calibrazione per modalità.** Calibrando con microfono e sensori si preparano anche le modalità solo microfono e solo sensori.
- **Suono breve** facoltativo quando un interruttore scatta.

### Miglioramenti
- **Pagina dei permessi con Accessibilità**, che serve alle azioni che premono un tasto.

## 0.1.0 · 2026-11-07
Prima versione: i tap sul tavolo accanto al Mac diventano 8 interruttori.

### Novità
- **Otto interruttori sul tavolo.** Doppio o triplo tap in uno dei quattro angoli intorno al Mac: Knock capisce dove e quante volte.
- **Microfono e sensore di movimento.** Sui MacBook con Apple Silicon (M2 e successivi) Knock usa anche l'accelerometro interno, che distingue meglio sinistra e destra.
- **Calibrazione guidata.** Una mappa del tavolo ti dice dove toccare e quante volte; in un minuto e mezzo Knock impara il tuo tavolo e ti dice quanto è preciso.
- **Pagina dei permessi.** All'avvio, se manca qualcosa, Knock mostra cosa serve, lo chiede e verifica dal vivo che il microfono senta davvero e che il sensore risponda; se il microfono resta bloccato, Reimposta cancella la decisione di macOS e la richiesta riparte.
- **Griglia nella barra dei menu.** Il quadrato della zona toccata si accende con il numero di tap; in pausa la griglia è tenue.
- **Niente falsi allarmi mentre scrivi.** Fino a un secondo dopo l'ultimo tasto i tap non contano.
- **Privacy.** Il suono resta in memoria per meno di due secondi e non viene mai salvato né inviato.
