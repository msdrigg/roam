---
tago_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Tungkol sa Roam

Ang Roam ay nag-aalok ng lahat ng gusto mo at wala kang hindi

-   Nagtatrabaho sa Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Matalinong pagsasama sa platform na may shortcut sa keyboard sa Mac, gamit ang mga pindutan ng lakas ng tunog ng hardware para i-control ang TV Volume sa iOS
-   Gamitin ang mga shortcut at widget para kontrolin ang iyong TV nang hindi kailanman binubuksan ang app!
-   Mga mode ng headphone (kilala rin bilang pakikinig na pampribado) suporta sa Mac, iPad, iPhone, VisionOS, at Apple TV (patugtugin ang audio mula sa iyong TV sa pamamagitan ng iyong device)
-   Matuklasan ang mga device sa iyong lokal na network kasabay ng pagbubukas mo ng app
-   Intuitibong disenyo gamit ang katutubong sistema ng disenyo ng SwiftUI ng Apple
-   Mabilis at magaan, mas mababa sa 8 MB sa lahat ng mga device at nagbubukas sa mas mababa sa kalahating segundo!
-   Bukas ang source (https://github.com/msdrigg/roam)

## Karaniwang mga Isyu

-   Ano ang magagawa ko kung hindi awtomatikong na-discobrir ng Roam ang aking TV
    -   [Tingnan dito](/manually-add-tv)
-   Bakit hindi gumagana ang mode ng mga headphone (a.k.a. pribadong pakikinig) sa aking TV?
    -   Sa kasalukuyan, ang mode ng mga headphone ay hindi gumagana sa ilang mga TV. Kung hindi gumagana ang mode ng mga headphone kasama ang Roam, ngunit gumagana sa opisyal na app ng Roku, paki-share ang pangalan ng modelo ng iyong Roku at anumang iba pang kaugnay na impormasyon sa isang email sa [roam-support@msd3.io](mailto:roam-support@msd3.io). Ang iyong ulat ay makatutulong sa akin na matukoy kung saan dapat tumingin sa pagtatangkang ayusin ang bug na ito.
-   Ano kung may iba pa akong problema o gusto lamang magbigay ng feedback?
    -   Kung ito ay isang bug, ang pinakamabuti ay magbigay ng feedback report mula sa aplikasyon
        -   Pumunta sa app ng Roam at buksan ang pahina ng mga setting
        -   I-click ang "Send feedback". Ito ay mag-generate ng isang diagnostic report na maaaring ibahagi sa roam support (roam-support@msd3.io)
        -   Kung ang iyong app ay nagko-crash, siguraduhin din na ang iyong mga analytics ay naka-on sa Settings -> Privacy & Security -> Analytics & Improvements
            -   I-on ang "Share iPhone & Watch Analytics" at pagkatapos ay i-on ang "Share With App Developers" para i-report ng apple sa akin kapag nag-crash ang iyong app
    -   Kung ito ay isang kahilingan para sa isang bagong tampok, maaari kang magpadala ng isang email direkta (roam-support@msd3.io) o mag-chat diretso sa akin sa Roam app (Settings -> Chat with the Developer)
-   Bakit hindi madalas gumagana ang mga pindutan ng arrow sa iPad?
    -   Ito ay dahil madalas na kinokontrol ng iPadOS ang mga pindutan ng arrow at ginagamit ito para i-navigate ang mga pindutan sa screen bago namin ito madetect
    -   Maaari mong i-lusot ito sa pamamagitan ng pagpunta sa Settings -> Accessibility -> Mga keyboard at i-disable ang "Full Keyboard Access" o kaya ay pumunta sa Settings -> Accessibility -> Keyboards -> Full Keyboard Access -> Commands -> Basic at i-disable ang mga command na "Move Up", "Move Down", "Move Left" at "Move Right"
-   Bakit hindi lumilitaw ang pag-type ko sa aking keyboard sa TV
    -   Sa ilang Roku Apps ang app ay nag-dedeadma sa pagpasok sa keyboard ng hardware. Maaari mong i-test kung ito ay isang bug ng Roam o isang bug sa app sa pamamagitan ng pagtatangkang gamitin ang keyboard entry feature sa opisyal na Roku App at suriin kung ito ay gumagana
    -   Apps na may nakilalang bugs
        -   Prime Video
-   Bakit gumagana ang Roam sa aking iPhone at mac app ngunit hindi sa aking Apple Watch?
    -   Ang WatchOS app ay konekta sa TV sa pamamagitan ng TV's ECP API, na dapat paganahin sa ilang mga Roku TV. Para paganahin ito, pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at tiyakin na ang "Network Access" ay naka-set sa "Permissive"

## Ibang Mga Resource

Kung mayroon kang anumang mga tanong o mga isyu, mangyaring kontakin ako sa: [roam-support@msd3.io](mailto:roam-support@msd3.io). Maaari mo rin akong makausap nang direkta sa Roam app (Settings -> Chat with the Developer).

-   [Privacy Policy](/privacy)
-   [Core Repository sa GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [I-download sa app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Changelog](/changes)
-   [Roku Devices na Natest](/tested-tvs)
