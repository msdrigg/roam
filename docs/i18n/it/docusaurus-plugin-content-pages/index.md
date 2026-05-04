---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Informazioni su Roam

Roam offre tutto ciò che desideri e niente di superfluo

-   Funziona su Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Integrazione intelligente con la piattaforma: scorciatoie da tastiera su Mac, utilizzo dei pulsanti del volume hardware per controllare il volume della TV su iOS
-   Usa scorciatoie e widget per controllare la tua TV senza mai aprire l'app!
-   Modalità cuffie (ovvero ascolto privato) supportata su Mac, iPad, iPhone, VisionOS e Apple TV (riproduce l'audio della TV tramite il tuo dispositivo)
-   Scopri i dispositivi sulla tua rete locale non appena apri l'app
-   Design intuitivo con il sistema di design nativo SwiftUI di Apple
-   Veloce e leggera, meno di 8 MB su tutti i dispositivi e si apre in meno di mezzo secondo!
-   Open source (https://github.com/msdrigg/roam)

## Funzionalità

-   Telecomando
    -   Roam include tutte le classiche funzioni del telecomando Roku, tra cui tasti direzionali, selezione, indietro, home, play/pausa e altri controlli correlati della TV supportati da Roku.
    -   I controlli del volume potrebbero non funzionare sui Roku Stick perché sono dispositivi solo HDMI e non possono controllare il volume della TV tramite i comandi di rete Roku di Roam.
-   Inserimento tramite tastiera
    -   Su macOS, non c'è un pulsante tastiera. Quando la finestra di Roam è attiva, la tastiera del Mac funziona automaticamente con la TV.
    -   Su iOS e iPadOS, c'è un pulsante tastiera in cima al telecomando.
    -   Al momento, watchOS non supporta la funzione tastiera.
    -   Alcune app Roku ignorano l’inserimento da tastiera tramite app remote. Prime Video, ad esempio, potrebbe non accettare l'inserimento perché l'app Roku non lo permette.
-   Modalità cuffie/ascolto privato
    -   L’ascolto privato consente di ascoltare l’audio della TV tramite il tuo dispositivo sui Roku supportati.
    -   L’ascolto privato è supportato su Roam per Mac, iPad, iPhone, VisionOS e Apple TV, ma non funziona su tutte le TV Roku.

## Problemi comuni

-   Cosa posso fare se Roam non rileva automaticamente la mia TV?
    -   [Vedi qui](/manually-add-tv)
-   Roam non funziona correttamente sul mio Apple Watch
    -   Vai su **Impostazioni -> Sistema -> Impostazioni Avanzate di Sistema -> Controllo tramite app mobili** e assicurati che sia impostato su **Permissivo**
-   Perché la modalità cuffie (ascolto privato) non funziona sulla mia TV?
    -   Al momento la modalità cuffie non funziona su alcune TV. Se con Roam non funziona ma con l'app ufficiale Roku sì, ti prego di inviare il modello della tua Roku e altre informazioni rilevanti a [roam-support@msd3.io](mailto:roam-support@msd3.io). Il tuo feedback mi aiuterà a individuare dove correggere questo bug.
-   Se ho un altro problema o voglio semplicemente lasciare un feedback?
    -   Se si tratta di un bug, è consigliabile inviare una segnalazione di feedback tramite l'applicazione
        -   Apri l'app Roam e vai nella pagina delle impostazioni
        -   Fai clic su "Invia feedback". Verrà generato un report diagnostico che può essere condiviso con il supporto Roam (roam-support@msd3.io)
        -   Se l'app si blocca, assicurati anche che l'analisi sia attivata in Impostazioni -> Privacy e sicurezza -> Statistiche & miglioramenti
            -   Attiva "Condividi Analisi iPhone & Watch" e poi "Condividi con gli sviluppatori dell’app" così Apple potrà segnalarmi eventuali crash dell'app
    -   Se si tratta di una richiesta per una nuova funzionalità, puoi inviare un'email (roam-support@msd3.io), chattare direttamente con me nell'app Roam (Impostazioni -> Chatta con lo sviluppatore) o unirti al [Discord di Roam](https://discord.gg/FqaTNRccbG).
-   Perché a volte i tasti freccia non funzionano su iPad?
    -   Ciò è dovuto al fatto che iPadOS a volte gestisce i tasti freccia per la navigazione dello schermo prima che possano essere rilevati dall'app
    -   Puoi risolvere andando su Impostazioni -> Accessibilità -> Tastiere e disattivando "Accesso completo alla tastiera" oppure, in alternativa, su Impostazioni -> Accessibilità -> Tastiere -> Accesso completo alla tastiera -> Comandi -> Base e disattivare i comandi "Sposta su", "Sposta giù", "Sposta a sinistra" e "Sposta a destra"
-   Perché quando digito sulla tastiera non appare nulla sulla TV?
    -   Su alcune app Roku, l’app ignora l’input da tastiera hardware. Puoi verificare se si tratta di un bug di Roam o dell'app tentando di usare la tastiera nell'app ufficiale Roku e controllando se funziona.
    -   Su macOS, non c'è un pulsante tastiera perché la tastiera del Mac funziona automaticamente con la TV quando la finestra Roam è attiva. Su iOS e iPadOS usa il pulsante tastiera nella parte superiore del telecomando. Al momento watchOS non supporta l’input da tastiera.
    -   App con bug noti:
        -   Prime Video
-   Perché Roam funziona su iPhone e su Mac ma non su Apple Watch?
    -   L'app WatchOS si collega alla TV tramite l'API ECP della TV, che deve essere abilitata su alcune TV Roku. Per abilitarla, vai su **Impostazioni -> Sistema -> Impostazioni Avanzate di Sistema -> Controllo tramite app mobili** e assicurati che "Accesso alla rete" sia impostato su "Permissivo"

## Altre risorse

Se hai domande o problemi, contattami a: [roam-support@msd3.io](mailto:roam-support@msd3.io). Puoi anche chattare direttamente con me all'interno dell'app Roam (Impostazioni -> Chatta con lo sviluppatore) oppure unirti al [Discord di Roam](https://discord.gg/FqaTNRccbG).

-   [Informativa sulla privacy](/privacy)
-   [Repository core su GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Scarica dall’App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Tabella di marcia](/upcoming-work)
-   [Changelog](/changes)
-   [Dispositivi Roku testati](/tested-tvs)