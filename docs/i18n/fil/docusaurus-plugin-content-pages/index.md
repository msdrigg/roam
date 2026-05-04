---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Tungkol sa Roam

Ang Roam ay nag-aalok ng lahat ng gusto mo at wala ang hindi mo kailangan

-   Gumagana sa Mac, iPhone, iPad, Apple Watch, Vision Pro, o Apple TV!
-   Matalinong integrasyon ng platform: may mga keyboard shortcut sa Mac, at maaaring gamitin ang hardware volume buttons para kontrolin ang TV Volume sa iOS
-   Gumamit ng shortcuts at widgets para kontrolin ang TV mo kahit hindi mo buksan ang app!
-   Sinusuportahan ang headphones mode (kilala rin bilang private listening) sa Mac, iPad, iPhone, VisionOS, at Apple TV (pakinggan ang audio ng TV sa iyong device)
-   Nadidiskubre agad ang mga device sa iyong lokal na network sa pagbukas ng app
-   Intuwitibong disenyo gamit ang native SwiftUI design system ng Apple
-   Mabilis at magaan—mas mababa sa 8 MB sa lahat ng device, at bumubukas sa loob ng kalahating segundo!
-   Open source (https://github.com/msdrigg/roam)

## Mga Tampok

-   Remote controls
    -   May kasamang mga normal na Roku remote control ang Roam: mga directional button, select, back, home, play/pause, at iba pang kaugnay na TV control depende sa suportang ibinibigay ng Roku.
    -   Ang volume control ay maaaring hindi gumana sa Roku Sticks dahil HDMI-only ang mga ito at hindi kayang kontrolin ang volume ng TV sa pamamagitan ng Roku network commands ni Roam.
-   Keyboard input
    -   Sa macOS, walang keyboard button. Kapag naka-focus ang Roam na window, awtomatikong gumagana ang Mac keyboard para sa TV.
    -   Sa iOS at iPadOS, may keyboard button sa itaas ng remote.
    -   Sa watchOS, wala pang keyboard functionality sa ngayon.
    -   May ilang mga Roku app na hindi tumatanggap ng keyboard input mula sa remote app. Halimbawa, ang Prime Video ay kilalang hindi tumatanggap ng keyboard entry dahil hindi ito sinusuportahan ng Roku app.
-   Headphones mode / private listening
    -   Pinapatugtog ng private listening ang audio ng TV sa iyong device para sa mga sinusuportahang Roku.
    -   Sinusuportahan ng Roam ang private listening sa Mac, iPad, iPhone, VisionOS, at Apple TV, ngunit hindi ito gumagana sa lahat ng Roku TV.

## Mga Karaniwang Isyu

-   Ano ang gagawin kapag hindi nade-detect ng Roam ang TV ko?
    -   [Tingnan dito](/manually-add-tv)
-   Hindi gumagana nang tama ang Roam sa Apple Watch ko
    -   Pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at tiyaking naka-set sa **Permissive**
-   Bakit hindi gumagana ang headphones mode (private listening) sa TV ko?
    -   Sa ngayon, hindi gumagana ang headphones mode sa ilang TV. Kung hindi gumagana ang headphones mode sa Roam, ngunit gumagana sa opisyal na Roku app, mangyaring ibahagi ang model name ng Roku mo at iba pang mahalagang impormasyon sa [roam-support@msd3.io](mailto:roam-support@msd3.io). Ang iyong report ay makakatulong upang malaman kung saan magsisimula ng pagtukoy para sa bug na ito.
-   Paano kung may iba pa akong problema o gusto lang magbigay ng feedback?
    -   Kung ito ay bug, pinakamainam na magsimula ng feedback report mula sa app
        -   Buksan ang Roam app at pumunta sa settings page
        -   I-tap ang "Send feedback". Magkakaroon ito ng diagnostic report na maari mong ipadala sa Roam support (roam-support@msd3.io)
        -   Kung crash ang app mo, siguraduhing naka-on ang analytics sa Settings -> Privacy & Security -> Analytics & Improvements
            -   I-on ang "Share iPhone & Watch Analytics" at pagkatapos i-on ang "Share With App Developers" para malaman ko kapag nagka-crash ang iyong app, mula mismo sa Apple
    -   Kung request ito para sa bagong feature, maaari kang magpadala ng email (roam-support@msd3.io), makipag-chat sa Roam app mismo (Settings -> Chat with the Developer) o sumali sa [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Bakit hindi minsan gumagana ang arrow keys sa iPad?
    -   Dahil paminsan-minsan, kinukuha ng iPadOS ang kontrol ng arrow keys at ginagamit ito para i-navigate ang mga screen button bago pa ito ma-detect ng Roam
    -   Pwedeng solusyon dito ay pumunta sa Settings -> Accessibility -> Keyboards at i-disable ang "Full Keyboard Access" o pumunta sa Settings -> Accessibility -> Keyboards -> Full Keyboard Access -> Commands -> Basic at i-off ang "Move Up", "Move Down", "Move Left" at "Move Right" commands
-   Bakit hindi lumalabas sa TV ang tina-type ko sa keyboard?
    -   Sa ilang Roku app, hindi pinapansin ang hardware keyboard entry. Para malaman kung bug ba ito sa Roam o bug sa app, subukan mong gamitin ang keyboard entry feature sa official Roku App at tingnan kung gumagana iyon.
    -   Sa macOS, walang keyboard button dahil awtomatikong gumagana ang Mac keyboard kapag naka-focus ang Roam window sa TV. Sa iOS at iPadOS, gamitin ang keyboard button sa taas ng remote. Walang keyboard support ang watchOS ngayon.
    -   Mga app na may kilalang isyu:
        -   Prime Video
-   Bakit gumagana ang Roam sa iPhone at Mac app ko pero hindi sa Apple Watch?
    -   Kumokonekta ang WatchOS app sa TV gamit ang TV's ECP API, na kailangang i-enable sa ilang Roku TV. Para i-on ito, pumunta sa **Settings -> System -> Advanced System Settings -> Control by mobile apps** at siguraduhing naka-set sa "Permissive" ang "Network Access"

## Iba pang Mga Mapagkukunan

Kung may mga tanong o isyu ka pa, makipag-ugnayan sa akin sa [roam-support@msd3.io](mailto:roam-support@msd3.io). Maaari ka ring makipag-chat sa akin direkta sa Roam app (Settings -> Chat with the Developer) o sumali sa [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Privacy Policy](/privacy)
-   [Core Repository on GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [I-download sa app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Changelog](/changes)
-   [Mga Nasubukang Roku Devices](/tested-tvs)