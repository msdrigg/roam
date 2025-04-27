---
tago_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Tungkol sa Roam

Nagbibigay ang Roam ng lahat ng gusto mo at wala kang ayaw

-   Gumagana sa Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Smart platform integration na may keyboard shortcuts sa Mac, gamit ang mga hardware volume buttons para kontrolin ang TV Volume sa iOS
-   Gamitin ang mga shortcuts at widgets upang kontrolin ang iyong TV nang hindi kailanman binubuksan ang app!
-   Headphones mode (a.k.a. pribadong pakikinig) support sa Mac, iPad, iPhone, VisionOS, at Apple TV (patugtugin ang audio mula sa iyong TV sa pamamagitan ng iyong aparato)
-   Matutuklasan ang mga aparato sa iyong lokal na network sa oras na binuksan mo ang app
-   Madaling gamitin na disenyo na may native SwiftUI design system ng apple
-   Mabilis at magaan, mas mababa sa 8 MB sa lahat ng mga aparato at nagbubukas sa mas mababa sa kalahating segundo!
-   Open source (https://github.com/msdrigg/roam)

## Karaniwang Isyu

-   Ano ang magagawa ko kung hindi awtomatikong matuklasan ng Roam ang aking TV
    -   [Tingnan dito](/manually-add-tv)
-   Bakit hindi gumagana ang headphones mode (a.k.a. private listening) sa aking TV?
    -   Kasalukuyang hindi gumagana ang headphones mode sa ilang TV. Kung hindi gumagana ang headphones mode na may Roam, pero gumagana sa opisyal na Roku app, mangyaring ibahagi ang iyong modelo ng Roku at anumang iba pang mahalagang impormasyon sa isang email sa [roam-support@msd3.io](mailto:roam-support@msd3.io). Ang iyong ulat ay makakatulong sa akin na malaman kung saan dapat tumingin kapag sinusubukang ayusin ang bug na ito.
-   Ano kung mayroon akong ibang problema o gusto lamang magbigay ng feedback?
    -   Kung ito'y isang bug, ito ay pinakamahusay na pumunta at magpasimula ng isang feedback report mula sa application
        -   Pumunta sa Roam app at buksan ang settings page
        -   I-click ang "Send feedback". Ito ay magpapalabas ng isang diagnostic na ulat na maaaring ibahagi sa suporta ng roam (roam-support@msd3.io)
        -   Kung ang iyong app ay nag-crash, siguraduhin din na ang iyong analytics ay naka-on sa Settings -> Privacy & Security -> Analytics & Improvments
            -   Buhayin ang "Share iPhone & Watch Analytics" at pagkatapos ay buhayin ang "Share With App Developers" upang ako'y makakuha ng ulat mula sa apple kung kailan nag-crash ang iyong app
    -   Kung ito'y isang kahilingan para sa isang bagong feature, maaari kang magpadala ng email (roam-support@msd3.io), makipag-usap sa akin nang direkta sa Roam app (Settings -> Chat with the Developer) o sumali sa [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Bakit hindi palaging nagana ang mga arrow keys sa iPad?
    -   Ito ay sanhi ng kontrol ng iPadOS sa mga arrow keys at ginagamit ito para na nag-navigate sa mga pindutan ng screen bago namin ito maaaring ma-detect
    -   Maaari mong i-work around ito sa pamamagitan ng pagpunta sa Settings -> Accessiblity -> Keyboards at hindi pinagana ang "Full Keyboard Access" o sa kabilang banda ay pagpunta sa Settings -> Accessiblity -> Keyboards -> Full Keyboard Access -> Commands -> Basic at hindi pinagana ang mga "Move Up", "Move Down", "Move Left" at "Move Right" na utos
-   Bakit hindi nagpapakita sa TV ang pag-type ko sa aking keyboard
    -   Sa ilang Roku Apps ang app ay hindi pinansin ang hardware keyboard entry. Maaari mong subukan kung ito ay isang bug ng Roam o bug sa app sa pamamagitan ng pagtatangkang gamitin ang keyboard entry feature sa opisyal na Roku App at sinusuri kung ito ay gumagana
    -   Mga Apps na may kilalang mga bug
        -   Prime Video
-   Bakit gumagana ang Roam sa aking iPhone at mac app pero hindi sa aking Apple Watch?
    -   Ang WatchOS app ay konektado sa TV sa pamamagitan ng ECP API ng TV, na dapat na pinagana sa ilang Roku TV. Upang paganahin ito, pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at siguraduhin na ang "Network Access" ay nakatakda sa "Permissive"

## Iba pang mga Resources

Kung mayroon kang anumang mga katanungan o isyu, mangyaring makipag-ugnay sa akin sa: [roam-support@msd3.io](mailto:roam-support@msd3.io). Maaari mo ring makipag-usap sa akin nang direkta sa Roam app (Settings -> Chat with the Developer) o sumali sa [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Patakaran sa Privacy](/privacy)
-   [Core Repository sa GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [I-download sa app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Changelog](/changes)
-   [Nasubok na Roku Devices](/tested-tvs)