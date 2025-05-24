---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Tungkol sa Roam

Binibigay ng Roam ang lahat ng gusto mo at wala ang hindi mo kailangan

-   Gumagana sa Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Matalinong integrasyon sa platform gamit ang keyboard shortcuts sa Mac, at paggamit ng hardware volume buttons para kontrolin ang TV Volume sa iOS
-   Gamitin ang mga shortcuts at widgets para kontrolin ang iyong TV kahit hindi mo buksan ang app!
-   Suporta para sa headphones mode (a.k.a. private listening) sa Mac, iPad, iPhone, VisionOS, at Apple TV (patugtugin ang audio ng TV sa iyong device)
-   Tuklasin agad ang mga device sa iyong local network kapag binuksan ang app
-   Intuwitibong disenyo gamit ang native SwiftUI design system ng Apple
-   Mabilis at magaan, hindi lalampas ng 8 MB sa lahat ng device at nagbubukas nang wala pang kalahating segundo!
-   Bukas na mapagkukunan (https://github.com/msdrigg/roam)

## Karaniwang mga Isyu

-   Ano ang gagawin ko kung hindi awtomatikong matuklasan ng Roam ang aking TV
    -   [Tingnan dito](/manually-add-tv)
-   Hindi maayos na gumagana ang Roam sa aking Apple Watch
    -   Pakitiyak na pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at siguraduhing naka-set sa **Permissive**
-   Bakit hindi gumagana ang headphones mode (a.k.a. private listening) sa aking TV?
    -   Sa kasalukuyan, hindi gumagana ang headphones mode sa ilang TV. Kung hindi gumagana ang headphones mode sa Roam, pero gumagana sa official Roku app, mangyaring ibahagi ang modelo ng iyong Roku at anumang kaugnay na impormasyon sa email na ito: [roam-support@msd3.io](mailto:roam-support@msd3.io). Makakatulong ang iyong ulat para matukoy ko ang sanhi ng bug na ito.
-   Paano kung may iba pa akong problema o gusto kong magbigay ng feedback?
    -   Kung bug ito, pinakamainam na magsumite ng feedback mula mismo sa application
        -   Buksan ang Roam app at pumunta sa settings page
        -   I-tap ang "Send feedback". Ito ay lilikha ng diagnostic report na maaaring ibahagi sa roam support (roam-support@msd3.io)
        -   Kung nagka-crash ang iyong app, tiyakin ding naka-on ang analytics mo sa Settings -> Privacy & Security -> Analytics & Improvments
            -   I-on ang "Share iPhone & Watch Analytics" at pagkatapos ay i-on ang "Share With App Developers" para malaman ko kapag nagka-crash ang app mo
    -   Para sa mga hiling na bagong feature, maaaring mag-email (roam-support@msd3.io), i-chat ako mismo sa Roam app (Settings -> Chat with the Developer) o sumali sa [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Bakit minsan hindi gumagana ang arrow keys sa iPad?
    -   Nangyayari ito dahil minsan ay kontrolado ng iPadOS ang arrow keys at ginagamit ang mga ito para mag-navigate sa screen buttons bago ito ma-detect ng app
    -   Maaaring gawing alternatibo ang pagpunta sa Settings -> Accessibility -> Keyboards at i-disable ang "Full Keyboard Access" o pumunta sa Settings -> Accessibility -> Keyboards -> Full Keyboard Access -> Commands -> Basic at i-disable ang mga "Move Up", "Move Down", "Move Left" at "Move Right" na commands
-   Bakit hindi lumalabas ang tinatype ko sa keyboard sa TV
    -   Sa ilang Roku Apps, hindi tinatanggap ng app ang hardware keyboard entry. Maaari mong subukin kung bug ito ng Roam o bug ng mismong app sa pamamagitan ng paggamit ng keyboard entry feature ng official Roku App at tingnan kung gumagana ito
    -   Mga App na may alam nang bug
        -   Prime Video
-   Bakit gumagana ang Roam sa aking iPhone at Mac app ngunit hindi sa Apple Watch?
    -   Kumokonekta ang WatchOS app sa TV gamit ang ECP API ng TV, na kailangang i-enable sa ilang Roku TV. Para i-enable, pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at tiyaking naka-set sa "Network Access" ang "Permissive"

## Iba Pang Mga Pinagkukunan

Kung may karagdagang mga tanong o isyu, mangyaring makipag-ugnayan sa akin sa: [roam-support@msd3.io](mailto:roam-support@msd3.io). Maaari mo rin akong i-chat nang direkta sa Roam app (Settings -> Chat with the Developer) o sumali sa [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Privacy Policy](/privacy)
-   [Core Repository sa GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [I-download sa app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Changelog](/changes)
-   [Mga Nasubukang Roku Devices](/tested-tvs)