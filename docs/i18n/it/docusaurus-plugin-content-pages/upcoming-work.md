---
hide_table_of_contents: true
---

# Lavorij più Recenti su Roam

# Prossimi Aggiornamenti di Roam

- Aggiunti widget di controllo: Play, Mute, Cambia Volume e Seleziona dal centro controllo!

## Roadmap

- Aggiorna la gestione della tastiera per supportare ecp-textedit su `KeyboardEntry`
    - Mostra la tastiera quando textedit viene aperto
    - Nascondi la tastiera quando textedit viene chiuso
    - Assicurati che l'incollamento + la selezione/eliminazione nel campo textedit funzioni come previsto
    - Utilizza il campo testo modificato corrente se ecp-textedit non è supportato, usa il campo testo standard se lo è
    - Su macOS, supporta l'incolla con cmdP, copia/taglia con cmdX + cmdC
    - Se ecp-textedit non è supportato, ritorna al comportamento corrente di invio delle chiavi
    - Su macOS mostra un campo di testo in basso quando è attivato textedit 
    - Su macOS permetti cmd+v e cmd+c e cmd+x per copiare/incollare da/nel buffer 

- Inserisci un timer mute di +30 secondi con countdown
    - Tieni premuto mute per silenziare per +30 secondi
    - Clicca di nuovo per disinserire il mute e annullarlo
    - Mostra un indicatore sotto la linea del pulsante mute 
        - La barra di progresso ha un indicatore di progresso lineare
        - La barra di progresso ha due pulsanti: +30 secondi, annulla
        - Mostra sotto il pannello principale dei pulsanti in modo che sia vicino al mute
    - Rendi il +30 configurabile per le opzioni mute di 30, 15, 60 secondi

- Fornisce una vista opzionale Minimalista su iOS che replica da vicino la vista del telecomando siri
    - https://support.apple.com/it-it/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Supporta le gesture di visionos anche...

## Idee Generali per il Futuro

- Scrivi un post sul blog riguardo il bot di Discord e fai riferimento al mio MessageView
- Scrivi un post sul blog riguardo l'auto-traduzione e la logica che la riguarda

- Crea l'icona personalizzata della barra dei menu

- Come fare il voice-to-text o comandi vocali generali?
    - Bisogna fare reverse-engineering del protocollo udp del telecomando vocale roku
    - O bisogna aggiungere un testo personalizzato da leggere con motore di comando remoto?

- Automatizzare la Cattura degli Screenshot

    - Utilizza i Test UI per ottenere screenshot reali
    - Utilizza AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w per ottenere gli screenshot nei frame
    - O qualcos'altro
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/it_it/templates/s/iphone/

- Testare altri trucchi con la tastiera
    - GCKeyboard per uno
    - FocusEnvironment per due
    - Assicurati che qualsiasi soluzione venga utilizzata per iOS non rompa l'input di testo nei messaggi/l'input della tastiera

- Aggiungi un qualche tracciamento degli eventi su cosa stanno effettivamente facendo gli utenti sui loro dispositivi (collegati a firebase analytics forse?)
    - Traccia chi sta usando la vista minimalista, quali azioni stanno eseguendo, etc...

## Correzioni di Bug

- Capire se il ciclo di chiamate a `nextPacket` ha senso.
    - Invece di fare un loop ogni 10ms e sperare che il tempo sia corretto, dovrei fare un loop sui pacchetti ricevuti e cercare di programmarli a host time `10ms * globalSequenceNumber + startHostTime` e sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    - Poi posso passare da un loop `for await` sull'orologio a un loop `while !Task.isCancelled` con un `Task.sleep` al suo interno.
    - Quindi abbiamo bisogno di fare un loop ogni 10 ms e cercare di ottenere l'ultimo pacchetto e poi programmarlo a quel tempo
    - Ogni volta che facciamo una sincronizzazione audio
        - Abbiamo lastRenderTime + un pacchetto di sincronizzazione
        - Stima il numero del pacchetto che dovremmo inviare + il tempo di sincronizzazione
            - Tempo di Rendering + aggiunta

## Migliora i Test

- Test UI
    - Testa quando un dispositivo viene aggiunto che compare nel selettore di dispositivi ed è selezionato da roam
    - Testa che l'utente possa navigare verso impostazioni -> dispositivi
    - Testa che l'utente possa navigare verso impostazioni -> messaggi
    - Testa che l'utente possa navigare verso impostazioni -> about
    - Testa che l'utente possa modificare/eliminare i dispositivi
    - Testa che l'utente possa cliccare sui pulsanti una volta aggiunti i dispositivi
    - Testa che l'utente veda il banner per nessun dispositivo quando compare
    - Testa che l'utente veda gli applinks
    - Fai riferimento a swiftdat testingmodelcontainer per i modelcontainers
    - Fai riferimento a qui https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad per come impostare i test

## App Clip

- AppClip
    - Aggiungi un pulsante "getAShareableLinkToThisDevice" su impostazioni -> dispositivo
        - Pre-generare tutti i 1.1M codici app clip e codifica le posizioni degli anelli (0.5GB)
        - Crea un pulsante per "Ricevi un link condivisibile al dispositivo!" con un'anteprima dell'immagine al codice app clip (colore roam)
        - Scarica il codice + link e convertilo in PNG sul dispositivo quando viene cambiata la posizione di un dispositivo
        - Fai sì che il codice apra il dispositivo come un link condiviso a un'immagine (con anteprima!)
    - Rendi anche il link del dispositivo reale condivisibile

## Migliora la messaggistica dell'utente riguardo la gestione delle informazioni/stato

- Aggiornare la gestione delle informazioni/stato per gestire meglio lo stato volatile
    - Al momento della disconnessione, selezione, click su pulsante, passando in primo piano, all'apertura dell'app -> Riparta il ciclo di riconnessione se scollegato
    - Il ciclo di riconnessione è per ritentare con backoff esponenziale le connessioni che falliscono (0.5s, raddoppia, 10s backoff)
    - Quando connesso al dispositivo, disabilita sempre gli avvisi di rete
    - Quando provi a connetterti al dispositivo, o provi ad accendere il dispositivo, mostra un'icona di informazione in rotazione invece del punto grigio
    - Quando accendi il dispositivo e riesci, mostra un'animazione nella transizione da grigio -> in rotazione -> verde
    - Quando accendi il dispositivo con WOL e non ti connetti dopo 5 secondi, o quando accendi il dispositivo e fallisci immediatamente, mostra un messaggio di avviso sotto quello del wifi
        - "Non siamo riusciti a svegliare il tuo Roku" (Scopri di più) (Non mostrare di nuovo per questo dispositivo), (X)
        - Scopri di più mostra alcune ragioni del perché
            - Non sei connesso alla stessa rete (Mostra l'ultimo nome della rete del dispositivo. Chiedi se l'utente è connesso a questa rete)
            - Il tuo dispositivo è in standby profondo (non è stato spento di recente) e non può essere risvegliato
                - Il tuo dispositivo non supporta WWOL ed è connesso al wifi
                - Il tuo dispositivo non supporta WWOL o WOL
            - La tua rete non è configurata in modo da permetterci di inviare comandi di risveglio al dispositivo
    - Il ciclo di riconnessione = Tentare con backoff esponenziale di ricollegarsi a riconnettere ECP
        - Riconnetti ECP prima
        - Ascolta le notifiche secondo
            - Gestisci +cambio-modo-energia,+apertura-textedit,+cambio-textedit,+chiusura-textedit,+cambio-nome-dispositivo
            - Assicurati che possiamo gestire ciascuna di queste richieste e il loro formato…
        - Aggiorna lo stato del dispositivo terzo
        - Aggiorna il testo-textedit stato quarto
            - Aggiorna lo stato textedit
        - Aggiorna le icone del dispositivo quinto
    - Su tutte le modifiche dopo la riconnessione (attraverso notifica o altro)
        - Aggiorna il Dispositivo (memorizzato) e StatoDispositivo (volatile)
    - Dopo la riconnessione/disconnessione, aggiorna lo stato online nella vista remota

## Migliora la messaggistica dell'utente riguardo le capacità del dispositivo

- Aggiorna la messaggistica dell'utente cuando possono verificarsi degli errori
    - Quando si clicca su un pulsante disabilitato, apri un popover per mostrare perché è disabilitato
        - Mostra un indicatore di informazione sul pulsante per indicare che possono essere ricevute informazioni quando viene cliccato?
        - Modalità cuffie disabilitata -> perché il dispositivo non supporta la modalità cuffie per questa app
        - Controllo del volume disabilitato -> perché l'audio viene inviato tramite HDMI che non supporta i controlli del volume?
    - Quando si sta attivamente cercando i dispositivie non ne vengono trovati di nuovi, mostra un messaggio di avviso sotto la lista dei dispositivi
        - "Non siamo riusciti a svegliare il tuo Roku" (Scopri Perché), (X)
        - Scopri di più mostra una finestra popup con alcune ragioni per cui ciò può verificarsi
            - Assicurati che il tuo dispositivo sia acceso e connesso alla stessa rete wifi della tua app. Se questo non funziona ancora, prova ad aggiungere il dispositivo manualmente.
            - Link https://roam.msd3.io/manually-add-tv.md e https://support.roku.com/article/115001480188 per ulteriori risoluzioni dei problemi o chatta
- Aggiungi l'emblema per supportsWakeOnWLAN e supportsMute

## Note ECP textedit

Comandi Sessione Tastiera ECP (note)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Da Aggiornare Quando si Smette di Supportare iOS 17/macOS 14 (Feb 2026)

- Rimuovi in giro le etichette @available(iOS 18)
- Utilizza le traits di anteprima per iniettare dati di esempio nelle anteprime
    - Come farlo ancora considerando iOS 17?
    - Come utilizzare @Previewable nelle anteprime con iOS 17 ancora considerato??
- SwiftData
    - Utilizza la nuova macro #Index per i modelli
    - Utilizza la nuova macro #Unique per i modelli
    - Utilizza la cancellazione batch
- TipKit
    - Utilizza CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698