---
hide_table_of_contents: true
---

# Aggiungere manualmente una TV

1. Trova l'indirizzo IP della tua TV
    - Accendi la tua TV e naviga verso **Impostazioni** > **Rete** > **Informazioni**
    - L'indirizzo IP dovrebbe apparire come 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - Questa pagina può elencare un indirizzo "Gateway" e un "Indirizzo IP". Assicurati di NON usare l'indirizzo "Gateway"
2. Naviga alle impostazioni di Roam e clicca su "Aggiungi un dispositivo manualmente"
3. Nominare il tuo dispositivo come preferisci, e inserisci l'IP del dispositivo esattamente come mostrato sulla TV Roku
4. Clicca Salva. Ora il tuo Roku dovrebbe essere in grado di connettersi e funzionare normalmente

## E se aggiungi la TV manualmente e Roam non riesce ancora a connettersi?

Se Roam non riesce ancora a controllare il tuo Roku, prova i seguenti passaggi

-   Assicurati che il tuo dispositivo iOS sia collegato alla stessa rete WiFi della tua TV Roku
-   Assicurati che la tua TV sia accesa
-   Assicurati che le autorizzazioni di Local Network siano abilitate per Roam (o disabilitala e riabilitala se è già abilitata)
    -   Su macOS: Vai su Impostazioni sistema -> Privacy e sicurezza -> Rete locale -> Roam
    -   Su iOS: Vai su Impostazioni -> App -> Roam -> Rete locale
-   Vedi le possibilità aggiuntive qui [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## E se ho una configurazione di rete / VPN complicata? Quali protocolli utilizza questa app?

-   Roam utilizza due protocolli diversi per comunicare con la TV
    -   TCP (HTTP/Websockets) sulla porta 8060 per inviare comandi alla TV
    -   WOL magic packet (UDP multicast all'indirizzo 255.255.255.255) per svegliare la TV dal sonno profondo
-   Tutte le TV Roku utilizzano la porta 8060 e non c'è modo di cambiarla dal lato TV. Ma se hai un tipo di configurazione di port forwarding e vuoi usare una porta in uscita diversa da Roam, è possibile. Devi solo inserire `<IP>:<Port>` nel campo "Indirizzo IP" invece di solo `<IP>`. Ad esempio, inserisci `192.168.8.242:8061` e la porta scelta verrà utilizzata.