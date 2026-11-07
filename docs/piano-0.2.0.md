# Knock 0.2.0: piano

## In breve

Si possono fare tutte e due le cose, e si aiutano a vicenda.

- **Senza microfono, solo sensori di movimento: sì.** A Mac fermo l'accelerometro ha un rumore di 0,00075 g
  (picchi fino a 0,005 g); i tap della prova arrivano a 0,037 g di mediana e mai sotto 0,027 g nel 90% dei casi:
  5 volte il picco del rumore. Nella prova la zona riconosciuta con i soli sensori era già al 96%. Vale solo per i
  MacBook con il sensore (M2 e successivi).
- **Azioni sugli interruttori: sì, tutte quelle della tua lista.** La maggior parte sono tasti mandati all'app in primo
  piano, quindi serve il permesso Accessibilità (si aggiunge alla pagina Permessi).

Raccomandazione: tre modalità di ascolto (microfono + sensori, solo sensori, solo microfono) e azioni divise in
**profili per app** (valgono solo quando quell'app è davanti) più un profilo **Sempre**. I due temi si incastrano: con
"Metti il muto al microfono" o "Spegni sensore", Knock può continuare ad ascoltare con i soli sensori e sentire il tap
che riaccende.

## Cosa si può fare e come

| Funzione | Come | Fattibilità |
|---|---|---|
| Solo sensori (senza microfono) | colpi rilevati come salto dell'accelerometro (soglia sul rumore misurato), zona dal classificatore già esistente | alta sui MacBook M2+, da misurare con una prova guidata come la prima |
| Doppio dx = approva, doppio sx = rifiuta (Claude) | Invio / Esc all'app in primo piano, solo nel profilo di Claude e del Terminale | alta; serve Accessibilità |
| Slide avanti / indietro | freccia destra / sinistra all'app in primo piano (Keynote, PowerPoint, Anteprima, browser) | alta; serve Accessibilità |
| Triplo alto sx = spegni sensore | pausa interna; con modalità "pausa leggera" resta in ascolto solo il gesto per riaccendere | alta |
| Triplo alto dx = apri un'app | NSWorkspace apre l'app scelta da un elenco | alta, nessun permesso |
| Triplo basso dx = muto al microfono | CoreAudio: muto del microfono di sistema (vale per tutte le app); lo stesso tap lo toglie | alta, nessun permesso; mentre è muto Knock passa da solo ai soli sensori |
| Altro, a piacere | Comando Rapido (`shortcuts run`), scorciatoia da tastiera libera, apri URL | alta |
| Profili per app | l'app in primo piano decide quale profilo vale; se non c'è, vale "Sempre" | alta |
| Conferma che è scattato | lampeggio nella barra (c'è già) più un suono breve facoltativo | alta |

## Limiti reali

- **Solo sensori:** niente sui Mac senza sensore (Intel, M1, desktop). Tastiera e trackpad fanno vibrare il Mac molto
  più di un tap sul tavolo: la regola "ignora mentre scrivi" diventa indispensabile. Un colpo forte sul tavolo o un
  oggetto appoggiato può scattare: si misura nella prova.
- **Tasti inviati:** vanno all'app in primo piano. Con i profili per app un "Invio" non finisce mai nell'app sbagliata,
  ma dentro Claude va a ciò che ha il fuoco (se stai scrivendo un messaggio, Invio lo manda).
- **Claude:** Invio = la scelta evidenziata (di solito "Sì"), Esc = no. Non c'è un modo ufficiale per sapere se in
  quel momento c'è una richiesta aperta. Più avanti si può fare meglio con un hook di Claude Code (la richiesta arriva
  a Knock, che aspetta il tap): è un lavoro a parte.
- **Muto:** è il muto del microfono di sistema, non quello di Zoom o Meet (per quelli: scorciatoia dell'app nel suo profilo).

## Vincoli di distribuzione

Nessuno nuovo: Accessibilità come gli altri permessi, ricordato tra un aggiornamento e l'altro grazie alla firma
locale di Nod. Prima release pubblica su GitHub e Homebrew: la 0.1.0 non esce da sola, le sue novità entrano nella 0.2.0.

## Piano di lavoro

1. **Prova guidata "solo sensori"** con `tapprobe` (stessa mappa, 64 gruppi + 30 s di digitazione): numeri su
   rilevamento, zone e falsi allarmi. Si prosegue se il rilevamento supera l'85%.
2. **Motore:** `MotionTapDetector` (salto dell'accelerometro) accanto al rilevatore audio; modalità di ascolto; passaggio
   automatico ai soli sensori quando il microfono è muto o negato. Calibrazioni separate per modalità.
3. **Azioni:** `Action` (apri app, tasto, Comando Rapido, URL, pausa, muto microfono), `Profile` (per app o Sempre),
   `ActionRunner`; scheda Impostazioni › Azioni con la griglia 2x2 e il doppio/triplo per ogni quadrato.
4. **Permessi:** Accessibilità nella pagina Permessi, chiesto solo se usi azioni con i tasti.
5. **Rilascio:** CHANGELOG 0.2.0, README, `release.sh` (release GitHub con DMG e cask nel tap).

## Domande (rispondi tipo "1a 2a 3b ...")

1. Modalità di ascolto: a) Microfono + sensori come predefinita, Solo sensori e Solo microfono a scelta (consigliato)
   b) Solo sensori come predefinita sui Mac che li hanno (niente pallino arancione) c) solo le due attuali.
2. Profili: a) per app in primo piano + "Sempre" (consigliato) b) solo "Sempre" (8 azioni fisse ovunque).
3. Claude: a) Invio / Esc nel profilo di Claude e del Terminale (consigliato) b) aspettare l'integrazione con l'hook di Claude Code.
4. Tipi di azione nella 0.2.0: a) apri app, tasto o scorciatoia, Comando Rapido, apri URL, pausa, muto microfono (consigliato) b) in più comandi shell liberi.
5. "Spegni sensore": a) pausa leggera: resta solo il gesto per riaccendere, con i soli sensori (consigliato) b) spegne tutto, si riaccende dal menu.
6. Conferma: a) lampeggio nella barra + suono breve facoltativo, spento di predefinito (consigliato) b) suono sempre.
7. Profili pronti all'installazione: a) sì: Claude, Terminale, Keynote, PowerPoint come nella tua lista, modificabili (consigliato) b) tutto vuoto.

## Risposte (2026-11-07)

- 1a: Microfono + sensori predefinita; Solo sensori e Solo microfono a scelta.
- 2a: profili per app in primo piano + "Sempre".
- 3a: Invio / Esc, e deve funzionare anche nell'app desktop di Claude (oltre al Terminale). I tasti della scheda di
  approvazione dell'app desktop vanno verificati sul Mac: nel profilo sono modificabili.
- 4a: apri app, tasto o scorciatoia, Comando Rapido, apri URL, pausa, muto microfono.
- 5: due azioni separate e configurabili: "Spegni il microfono" (resta l'ascolto con i soli sensori) e "Spegni tutti i
  sensori" (risparmio batteria: niente resta in ascolto, si riaccende solo dal menu).
- 6a: lampeggio + suono breve facoltativo, spento di predefinito.
- 7a: profili pronti per Claude (desktop e Terminale), Keynote, PowerPoint, più "Sempre" con le azioni della lista.
