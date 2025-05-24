---
hide_table_of_contents: true
---

# Manu-manong Pagdagdag ng TV

1. Hanapin ang IP Address ng iyong TV
    - I-on ang iyong TV at pumunta sa **Settings** > **Network** > **About**
    - Ang IP Address ay dapat mukhang 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - Sa page na ito, maaaring makita mo ang "Gateway" address at "IP Address". Siguraduhing HINDI mo ginagamit ang "Gateway" address
2. Pumunta sa mga settings ng Roam at pindutin ang "Add a device manually"
3. Bigyan ng pangalan ang iyong device kung paano mo gusto, at ilagay nang eksakto ang IP ng device gaya ng ipinapakita sa iyong Roku TV
4. Pindutin ang Save. Ngayon, dapat na makakonekta ang iyong Roku at normal nang gumana

## Paano kung nadagdag mo na nang manu-mano ang TV pero hindi pa rin makakonekta ang Roam o hindi maayos ang koneksyon?

Kung hindi pa rin makontrol ng Roam ang iyong Roku, subukan ang mga sumusunod na hakbang

-   [WatchOS LAMANG]: Mangyaring pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at siguraduhing naka-set ito sa **Permissive**
-   Siguraduhing ang iyong iOS device ay nakakonekta sa parehong WiFi network tulad ng iyong Roku TV
-   Siguraduhing nakabukas ang iyong TV
-   Siguraduhing naka-enable ang Local Network Permissions para sa Roam (o i-disable at i-enable ulit ito kung naka-enable na)
    -   Sa macOS: Pumunta sa System Settings -> Privacy and Security -> Local Network -> Roam
    -   Sa iOS: Pumunta sa Settings -> Apps -> Roam -> Local Network
-   Tingnan ang iba pang mga posibilidad dito [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Paano kung komplikado ang aking network/VPN setup? Anong mga protocol ang ginagamit ng app na ito?

-   Maraming magkaibang protocol ang ginagamit ng Roam para makipag-ugnayan sa TV
    -   TCP (HTTP/Websockets) sa port 8060 para magpadala ng mga command sa TV at mag-query ng device state
    -   WOL magic packet (UDP multicast sa address 255.255.255.255) para gisingin ang TV mula sa deep sleep
    -   RDP (UDP) sa port 6970 para sa audio stream ng headphones mode
-   Lahat ng Roku TV ay gumagamit ng port 8060 at walang paraan para palitan ito sa panig ng TV. Ngunit kung may naka-setup kang port forwarding at nais gumamit ng ibang outgoing port mula sa Roam, posible ito. Kailangan mo lang ilagay ang `[IP]:[Port]` sa "Ip Address" field imbis na simpleng `[IP]`. Halimbawa, ilagay ang `192.168.8.242:8061` at ang port `8061` ang gagamitin.