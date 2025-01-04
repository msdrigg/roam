---
tago_table_of_contents: true
---

# Manwal na Pagdaragdag ng TV

1. Hanapin ang IP Address ng iyong TV
    - I-on ang iyong TV at mag-navigate sa **Settings** > **Network** > **About**
    - Ang IP Address ay dapat magmukhang katulad ng 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - Maaaring ilista ng pahinang ito ang "Gateway" address at ang "IP Address". Siguraduhing HINDI mo ginagamit ang "Gateway" address
2. Mag-navigate sa mga setting ng Roam at i-click ang "Manually Add a device"
3. Pangalanan mo ang iyong device sa anumang gusto mo, at i-enter ang IP ng device tulad ng ipinapakita sa Roku TV
4. I-click ang Save. Ngayon, dapat makakonekta at gumana nang normal ang iyong Roku

## Paano kung idinagdag mo ang TV nang manu-man29 file://localhost/Users/lennyojumu/Desktop/jukin%20stuff/Transcriptions/Task/2272464.html o at hindi pa rin makakonekta ang Roam?

Kung hindi pa rin makapag-kontrol ng iyong Roku ang Roam, mangyaring subukan ang mga sumusunod na hakbang

-   Siguraduhing nakakonekta ang iyong iOS device sa parehas na WiFi network bilang ang iyong Roku TV
-   Siguraduhing nakabukas ang iyong TV
-   Siguraduhing pinagana ang Local Network Permissions para sa Roam (o patayin at muling paganahin kung ito'y na-enable na)
    -   Sa macOS: Tumungo sa System Settings -> Privacy and Security -> Local Network -> Roam
    -   Sa iOS: Tumungo sa Settings -> Apps -> Roam -> Local Network
-   Tingnan ang karagdagang mga posibilidad dito [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Paano kung may komplikadong network/VPN setup ako? Anu-ano ang mga protocol na ginagamit ng app na ito?

-   Ang Roam ay gumagamit ng dalawang iba't-ibang mga protocol para komunikahin ang TV
    -   TCP (HTTP/Websockets) sa port 8060 para sa pagpadala ng mga utos papunta sa TV
    -   WOL magic packet (UDP multicast sa address na 255.255.255.255) para gisingin ang TV mula sa malalim na tulog
-   Ang lahat ng Roku TV's ay gumagamit ng port 8060 at walang paraang magpalit nito sa panig ng TV. Ngunit kung meron kang setup ng port forwarding at gusto mong gumamit ng ibang outgoing port mula sa Roam, posible ito. Kailangan mo lamang na i-input ang `<IP>:<Port>` sa field na "Ip Address" imbes na `<IP>` lamang. Hal. i-input ang `192.168.8.242:8061` at gagamitin ang napiling port.