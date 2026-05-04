---
hide_table_of_contents: true
---

# Manu-manong Pagdaragdag ng TV

1. Hanapin ang IP Address ng iyong TV
    - Buksan ang iyong TV at pumunta sa **Settings** > **Network** > **About**
    - Kung wala kang pisikal na remote o ibang paraan para makontrol ang TV, tingnan ang admin interface ng iyong home router o ang DHCP client list para makita ang IP address ng Roku
    - Karaniwang ganito ang itsura ng IP Address: 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - Maaari ring makita sa page na ito ang "Gateway" address at "IP Address". Siguraduhing HINDI ang "Gateway" address ang gagamitin mo
2. Pumunta sa Roam settings at i-click ang "Add a device manually"
3. Bigyan ng pangalan ang iyong device ayon sa gusto mo, at ilagay nang eksakto ang IP address gaya ng nakalagay sa Roku TV
4. I-click ang Save. Ngayon, dapat makakonekta at gumana na nang normal ang iyong Roku

## Paano kung manu-manong mo nang naidagdag ang TV pero hindi pa rin makakonekta ang Roam o hindi gumagana nang tama ang koneksyon?

Kung hindi pa rin makontrol ng Roam ang iyong Roku, subukan ang sumusunod na mga hakbang

-   [WatchOS LAMANG]: Pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at tiyaking naka-set ito sa **Permissive**
-   Siguraduhin na ang iyong iOS device ay nakakonekta sa parehong WiFi network ng iyong Roku TV
-   Siguraduhing naka-on ang iyong TV
-   Siguraduhing naka-enable ang Local Network Permissions para sa Roam (o i-disable at i-enable ulit kung naka-enable na)
    -   Sa macOS: Pumunta sa System Settings -> Privacy and Security -> Local Network -> Roam
    -   Sa iOS: Pumunta sa Settings -> Apps -> Roam -> Local Network
-   Kung nagbago ang configuration ng iyong home network at biglang hindi na gumagana ang dating gumaganang device, tanggalin muna ito mula sa Roam at i-scan muli
-   Kung hindi nakakonekta sa WiFi ang Roku at wala kang pisikal na remote, sundan ang step sa mobile app ng Roku dito: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Tingnan pa ang iba pang posibleng solusyon dito [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Paano kung komplikado ang setup ng network/VPN ko? Anong mga protocol ang ginagamit ng app na ito?

-   Gumagamit ang Roam ng iba’t ibang protocol para makipag-ugnayan sa TV
    -   TCP (HTTP/Websockets) sa port 8060 para magpadala ng commands sa TV at i-query ang device state
    -   WOL magic packet (UDP multicast sa address 255.255.255.255) para gisingin ang TV mula sa deep sleep
    -   RDP (UDP) sa port 6970 para sa headphones mode audio stream
-   Lahat ng Roku TV ay gumagamit ng port 8060 at walang paraan para palitan ito sa TV side. Ngunit kung may port forwarding setup ka at gustong gumamit ng ibang outgoing port mula sa Roam, posible ito. Kailangan lang ilagay ang `[IP]:[Port]` sa "Ip Address" field imbes na purong `[IP]` lang. Halimbawa, ilagay ang `192.168.8.242:8061` at ang port na `8061` ang gagamitin.