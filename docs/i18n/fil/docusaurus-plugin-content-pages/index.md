---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Tungkol sa Roam

Ang Roam ay nag-aalok ng lahat ng gusto mo at wala kang hindi 

-   Tumatakbo sa Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Smart platform integration na may mga shortcut sa keyboard sa Mac, paggamit ng mga hardware volume button upang kontrolin ang TV Volume sa iOS
-   Gamitin ang mga shortcut at widgets upang kontrolin ang TV mo nang hindi binubuksan ang app!
-   Headphones mode (a.k.a. private listening) support sa Mac, iPad, iPhone, VisionOS, at Apple TV (magpatugtog ng audio mula sa iyong TV sa pamamagitan ng iyong device)
-   Matuklasan ang mga device sa iyong lokal na network sa oras na binubuksan mo ang app
-   Intuitive design na may native SwiftUI design system ng apple
-   Mabilis at magaan, mas mababa sa 8 MB sa lahat ng mga device at nagbubukas sa mas mababa sa kalahating segundo!
-   Open source (https://github.com/msdrigg/roam)

## Karaniwang Mga problema

-   Ano ang magagawa ko kung hindi kusang natutuklasan ng Roam ang aking TV
    -   [Tingnan dito](/manually-add-tv)
-   Bakit hindi gumagana ang headphones mode (a.k.a. private listening) sa aking TV?
    -   Sa kasalukuyan, hindi gumana ang headphones mode sa ilang mga TV. Kung hindi gumagana ang headphones mode kasama ang Roam, ngunit gumagana sa opisyal na app ng Roku, pakishare ang pangalan ng modelo ng iyong Roku at anumang iba pang makabuluhang impormasyon sa isang email papunta sa [roam-support@msd3.io](mailto:roam-support@msd3.io). Makatutulong ang iyong ulat sa akin upang malaman kung saan hahanapin kapag sinusubukan na ayusin ang bug na ito.
-   Ano kung may iba pa akong problema o nais lamang magbigay ng feedback?
    -   Kung itoy bug, ito ay pinakamahusay na magpasa ng isang feedback report mula sa application
        -   Pumunta sa app ng Roam at buksan ang pahina ng mga setting
        -   Pindutin ang "Send feedback". It will generate a diagnostic report na maipapadala sa roam support (roam-support@msd3.io)
        -   Kung nagkakacrash ang iyong app, siguraduhin din na ang iyong analytics ay turned on sa Settings -> Privacy & Security -> Analytics & Improvements
            -   I-on ang "Share iPhone & Watch Analytics" at pagkatapos i-on ang "Share With App Developers" upang mag-report sa akin ang apple kapag nag-crash ang iyong app
    -   Kung ito ay ang isang kahilingan para sa isang bagong feature, maaari kang magpadala ng diretsong email (roam-support@msd3.io) o makipag-usap sa akin nang direkta sa app ng Roam (Settings -> Chat with the Developer)
-   Bakit hindi minsan gumagana ang mga arrow key sa iPad?
    -   Ito ay dahil itinakda ng iPadOS na kontrolin ang mga arrow key at ginagamit ang mga ito para sa pag-navigate ng screen buttons bago namin madetect ang mga ito
    -   Maaari kang maka-iwas sa problemang ito sa pamamagitan ng pagpunta sa Settings -> Accessibility -> Keyboards at pag-disable ng "Full Keyboard Access" o kaya'y pumunta sa Settings -> Accessibility -> Keyboards -> Full Keyboard Access -> Commands -> Basic at i-disable ang "Move Up", "Move Down", "Move Left" at "Move Right" commands
-   Bakit hindi nagpapakita ang pag-tatype ko sa aking keyboard sa TV
    -   Sa ilang Apps ng Roku ang app ay nag-iignore ng hardware keyboard input. Maari mong subukan kung ito ay isang bug ng Roam o ng app sa pamamagitan ng pagsubok na gamitin ang keyboard entry feature sa opisyal na Roku App at tingnan kung ito ay gumagana
    -   Mga apps na may sikat na mga bugs
        -    Prime Video
-   Bakit gumagana ang Roam sa aking iPhone at mac app pero hindi sa aking Apple Watch?
    -   Ang WatchOS app ay nakakonekta sa TV sa pamamagitan ng TV's ECP API, na kailangan i-enable sa ilang Roku TV's. Upang i-enable ito, pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at siguraduhing ang "Network Access" ay itinakda sa "Permissive"

## Ibang Resources

Kung mayroon kang mga tanong o problema, mangyaring makipag-ugnay sa akin sa: [roam-support@msd3.io](mailto:roam-support@msd3.io). Maaari mo rin akong makausap nang direkta sa app ng Roam (Settings -> Chat with the Developer).

-   [Patakaran sa Pagkapribado](/privacy)
-   [Core Repository sa GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Idownload sa app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Mga Roku Devices na Natest](/tested-tvs)