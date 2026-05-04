---
hide_table_of_contents: true
---

# Aggiunta manuale di una TV

1. Trova l'indirizzo IP della tua TV
    - Accendi la TV e vai su **Impostazioni** > **Rete** > **Informazioni**
    - Se non hai un telecomando fisico o un altro modo per controllare la TV, controlla invece l'interfaccia di amministrazione del tuo router di casa o l'elenco dei client DHCP per trovare l'indirizzo IP della Roku
    - L'indirizzo IP dovrebbe assomigliare a 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - In questa pagina potrebbero essere elencati sia un indirizzo "Gateway" che un "Indirizzo IP". Assicurati di NON usare l'indirizzo "Gateway"
2. Vai alle impostazioni di Roam e clicca su "Aggiungi un dispositivo manualmente"
3. Dai un nome al tuo dispositivo come preferisci e inserisci l'indirizzo IP esattamente come mostrato sulla Roku TV
4. Clicca su Salva. Ora la tua Roku dovrebbe potersi connettere e funzionare normalmente

## Cosa succede se aggiungi manualmente la TV ma Roam non riesce comunque a connettersi o la connessione non funziona correttamente?

Se Roam non riesce ancora a controllare la tua Roku, prova questi passaggi

-   [Solo WatchOS]: Vai su **Impostazioni -> Sistema -> Impostazioni avanzate di sistema -> Controllo tramite app mobili** e assicurati che sia impostato su **Permissivo**
-   Assicurati che il tuo dispositivo iOS sia connesso alla stessa rete WiFi della tua Roku TV
-   Assicurati che la TV sia accesa
-   Assicurati che i permessi per la rete locale siano abilitati per Roam (oppure disabilita e riabilita se già abilitato)
    -   Su macOS: Vai su Impostazioni di Sistema -> Privacy e Sicurezza -> Rete Locale -> Roam
    -   Su iOS: Vai su Impostazioni -> App -> Roam -> Rete Locale
-   Se la configurazione della rete domestica è cambiata e un dispositivo che funzionava non funziona più, elimina il dispositivo salvato da Roam e cercalo di nuovo
-   Se la Roku non è connessa al WiFi e non hai un telecomando fisico, segui i passaggi per la connessione tramite app mobile Roku qui: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Consulta altre possibili soluzioni qui [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## E se ho una configurazione di rete/VPN complessa? Quali protocolli utilizza questa app?

-   Roam utilizza diversi protocolli per comunicare con la TV
    -   TCP (HTTP/Websocket) sulla porta 8060 per inviare comandi alla TV e verificare lo stato del dispositivo
    -   Pacchetto magico WOL (UDP multicast all’indirizzo 255.255.255.255) per riattivare la TV dalla modalità deep sleep
    -   RDP (UDP) sulla porta 6970 per lo streaming audio della modalità cuffie
-   Tutte le Roku TV usano la porta 8060 e non è possibile modificarla lato TV. Ma se hai una configurazione di port forwarding e vuoi usare una porta diversa in uscita da Roam, è possibile. È sufficiente inserire `[IP]:[Port]` nel campo "Indirizzo IP" invece di solo `[IP]`. Ad esempio, inserisci `192.168.8.242:8061` e verrà utilizzata la porta `8061`.