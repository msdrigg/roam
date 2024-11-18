---
nascondi_indice_contenuti: true
---

# Roam Roadmap

## Lavoro completato per il prossimo aggiornamento

- Aggiunti widget di controllo: Riproduci, Mute, Cambia volume e Seleziona dal centro di controllo!
- Migliorata la gestione del campo di testo per molte applicazioni roku
    - Auto-apertura del campo di testo quando è disponibile la modifica del testo
    - Copia, Taglia, Incolla da macOS
    - Copia, Taglia, Incolla + modifica generalizzata su iOS
- Miglioramenti nella segnalazione relativa ai permessi della rete locale e alla connettività
- Miglioramenti alla stabilità della connessione

## In arrivo

-   Attualmente in corso
    -   Assicurarsi che l'inserimento del testo su iOS non vada al di sotto della tastiera (come sta facendo ora)
    -   Riparare i widget macOS
    -   Far uscire la versione iOS sull'app store
        - Aspettare il seguito dell'appello
    -   Effettuare test più accurati su iOS e macOS per verificare che il sistema si riconnetta e rimanga connesso nei seguenti scenari
        - Dopo un lungo periodo di tempo
        - Quando si rientra dallo sfondo
        - Quando si accende la TV dallo stato OFF
        - Quando ci si ricollega a Internet
        - Quando si cambia dispositivo

-   Successivo: Aggiungi un temporizzatore di mute di +30 secondi con countdown
    -   Mantieni mute per silenziare per +30 secondi
    -   Clicca di nuovo per disattivare il muto e annullarlo
    -   Mostra un indicatore sotto la linea del pulsante mute
        -   La barra di progresso ha un indicatore di progresso lineare
        -   La barra di progresso ha due pulsanti: +30 secondi, annulla
        -   Mostra sotto il pannello principale dei pulsanti in modo che sia vicino al muto
    -   Rendere il +30 configurabile a 30, 15, 60 opzioni di mute secondi

-   Futuro: Fornire una vista minimalista opzionale su iOS che replica da vicino la vista del telecomando siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Supporta le gesture di visionos...

## Idee future generali

-   Scrivere un post sul blog riguardo il bot di discord e indirizzare al mio MessageView
    - Rendere MessageView più autonomico
-   Scrivere un post sul blog riguardo alla traduzione automatica e alla logica ad essa associata
-   Scrivere un post sul blog riguardo NWConnection vs URLSession per i websockets
-   Scrivere un post sul blog riguardo alle scelte dei tasti di scelta rapida personalizzati
-   Scrivere un post sul blog riguardo l'API ECP Textedit
-   Scrivere un post sul blog riguardo ai widget del centro di controllo

-   Creare una icona personalizzata per la barra dei menu

-   Come fare il riconoscimento vocale o i comandi vocali in generale?
    - Bisogna retro-engineerizzare il protocollo udp del telecomando vocale roku
    - O bisogna aggiungere un riconoscimento del testo vocale personalizzato con il motore dei tasti del telecomando?

-   Automatizzare la cattura delle schermate

    -   Utilizzare UITests per ottenere schermate reali per tutte le dimensioni dei dispositivi + località
    -   Utilizzare AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w per ottenere le schermate nei frame
    -   O qualcos'altro
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Prova ulteriori tecniche con la tastiera per iPad
    -   GCKeyboard per uno
    -   FocusEnvironment per 2
    -   Assicurarsi che qualsiasi soluzione venga utilizzata per iOS non interrompa l'inserimento del testo nei messaggi/l'inserimento dalla tastiera

-   Test dell'interfaccia utente
    -   Testare quando viene aggiunto un dispositivo che appare nel selettore di dispositivi ed è selezionato da roam
    -   Testare che l'utente può navigare verso impostazioni -> dispositivi
    -   Testare che l'utente può navigare verso impostazioni -> messaggi
    -   Testare che l'utente può navigare verso impostazioni -> informazioni
    -   Testare che l'utente può modificare/eliminare i dispositivi
    -   Testare che l'utente può cliccare sui pulsanti una volta che i dispositivi sono aggiunti
    -   Testare che l'utente vede il banner per nessun dispositivo quando appare
    -   Testare che l'utente vede i collegamenti applicazione
    -   Fare riferimento a swiftdat testingmodelcontainer per modelcontainers
    -   Fare riferimento a qui https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad per come impostare i test

## Correzioni di bug

-   Capire se il ciclo di chiamate a `nextPacket` ha senso.
    -   Invece di fare il loop ogni 10ms e sperare che il tempo sia corretto, dovrei loopare sui pacchetti ricevuti e cercare di programmarli al tempo dell'host `10ms * globalSequenceNumber + startHostTime` e sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Quindi posso passare da un loop `for await` sul clock a un loop `while !Task.isCancelled` con un `Task.sleep` al suo interno.
    -   Ok, quindi dobbiamo fare un loop ogni 10 ms e cercare di prelevare l'ultimo pacchetto e quindi programmarlo in quel momento
    -   Ogni volta che facciamo un sincronismo audio
        -   Abbiamo lastRenderTime + un pacchetto di sincronizzazione
        -   Stimare il numero del pacchetto che dovremmo inviare + il tempo di sincronizzazione
            -   Render Time + additional

## Migliorare il messaggio dell'utente intorno alla gestione delle informazioni/stato/capacità

-   Quando si accende il dispositivo con WOL e non ci si collega dopo 5 secondi, o quando si accende il dispositivo e si fallisce immediatamente, mostrare un messaggio di avviso sotto a quello del wifi
    -   “Non siamo riusciti a risvegliare il tuo Roku” (Scopri di più) (Non mostrare di nuovo per questo dispositivo), (X)
    -   Scopri di più mostra alcuni motivi possibili
        -   Non sei connesso alla stessa rete (Mostra l'ultimo nome della rete del dispositivo. Chiedi all'utente se è connesso a questa rete)
        -   Il tuo dispositivo è in modalità di sonno profondo (non è stato spento di recente) e non può essere risvegliato
            -   Il tuo dispositivo non supporta WWOL ed è connesso al wifi
            -   Il tuo dispositivo non supporta WWOL o WOL
        -   La tua rete non è configurata in modo da consentirci di inviare comandi di risveglio al dispositivo
-   Quando si fa clic su un pulsante disabilitato, mostrare una notifica che indica il motivo per cui è disabilitato
    -   Mostra un indicatore di informazioni sul pulsante per indicare che le informazioni possono essere ricevute quando viene cliccato?
    -   La modalità cuffie disabilitata -> perché il dispositivo non supporta la modalità cuffie per questa app
    -   Controllo del volume disabilitato -> perché l'audio è trasmesso via HDMI che non supporta i controlli del volume?
-   Quando si scansiona attivamente per i dispositivi e non se ne trovano di nuovi, mostrare un messaggio di avviso sotto l'elenco dei dispositivi
    -   “Non siamo riusciti a risvegliare il tuo Roku” (Scopri perché), (X)
    -   Scopri di più mostra una finestra popup con alcuni motivi per cui questo potrebbe accadere
        -   Assicurati che il tuo dispositivo sia acceso e connesso alla stessa rete wifi dell'app. Se non funziona ancora, prova ad aggiungere il dispositivo manualmente.
        -   Link https://roam.msd3.io/manually-add-tv.md e https://support.roku.com/article/115001480188 per ulteriori risoluzione dei problemi o chat
-   Aggiungi un badge per supportsWakeOnWLAN e supportsMute

## Da aggiornare quando si abbandona il supporto per iOS 17/macOS 14 (Feb 2026)

-   Girare e rimuovere le etichette @available(iOS 18)
-   Usare caratteristiche di anteprima per iniettare dati di esempio nelle anteprime
-   SwiftData
    -   Utilizzare la nuova macro #Index per i modelli
    -   Utilizzare la nuova macro #Unique per i modelli
    -   Utilizzare la cancellazione in batch
-   TipKit
    -   Utilizzare CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698