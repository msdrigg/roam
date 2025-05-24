---
hide_table_of_contents: true
---

# Aggiunta manuale di una TV

1. Trova l'indirizzo IP della tua TV
    - Accendi la tua TV e vai su **Impostazioni** > **Rete** > **Informazioni**
    - L'indirizzo IP dovrebbe avere un aspetto simile a 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - In questa pagina potrebbero essere elencati un indirizzo "Gateway" e un "Indirizzo IP". Assicurati di NON utilizzare l'indirizzo "Gateway"
2. Vai alle impostazioni di Roam e clicca su "Aggiungi un dispositivo manualmente"
3. Dai al tuo dispositivo il nome che preferisci e inserisci l'indirizzo IP esattamente come visualizzato sulla Roku TV
4. Clicca su Salva. Ora il tuo Roku dovrebbe essere in grado di connettersi e funzionare normalmente

## Cosa fare se aggiungi la TV manualmente e Roam ancora non riesce a connettersi o la connessione non funziona correttamente?

Se Roam non riesce ancora a controllare il tuo Roku, prova i seguenti passaggi

-   [Solo WatchOS]: Vai su **Impostazioni -> Sistema -> Impostazioni di sistema avanzate -> Controllo tramite app mobili** e assicurati che sia impostato su **Permissivo**
-   Assicurati che il tuo dispositivo iOS sia connesso alla stessa rete WiFi della tua Roku TV
-   Assicurati che la TV sia accesa
-   Assicurati che le autorizzazioni per la rete locale siano abilitate per Roam (oppure disabilitale e riabilitale se sono già abilitate)
    -   Su macOS: Vai su Impostazioni di sistema -> Privacy e sicurezza -> Rete locale -> Roam
    -   Su iOS: Vai su Impostazioni -> App -> Roam -> Rete locale
-   Consulta altre possibili soluzioni qui [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## E se ho una rete/VPN complessa? Quali protocolli utilizza questa app?

-   Roam utilizza diversi protocolli per comunicare con la TV
    -   TCP (HTTP/Websockets) sulla porta 8060 per inviare comandi alla TV e interrogare lo stato del dispositivo
    -   Pacchetto magico WOL (UDP multicast all'indirizzo 255.255.255.255) per riattivare la TV dalla modalità di risparmio energia profonda
    -   RDP (UDP) sulla porta 6970 per lo streaming audio della modalità cuffie
-   Tutte le Roku TV utilizzano la porta 8060 e non è possibile cambiarla dal lato TV. Tuttavia, se hai un tipo di configurazione con port forwarding e desideri utilizzare una porta diversa in uscita da Roam, è possibile. Devi solo inserire `[IP]:[Porta]` nel campo "Indirizzo IP" invece di solo `[IP]`. Ad esempio, inserisci `192.168.8.242:8061` e verrà utilizzata la porta `8061`.