---
hide_table_of_contents: true
---

# Roam Roadmap

## Natapos na Trabaho para sa Susunod na Update

- Nagdagdag ng control widgets: I-play, I-mute, Baguhin ang Volume at Pumili mula sa Control center!
- Nagdagdag ng mas mahusay na pag-handle ng text field para sa maraming mga roku app 
    - Auto-open text field kapag magagamit ang text edit 
    - Kopyahin, Putulin, Idikit mula sa macOS
    - Kopyahin, Putulin, Idikit + Naipamamahagiang pag-edit sa iOS
- Mas mahusay na reporting sa paligid ng mga pahintulot sa local network at konektibidad
- Mga pagpapabuti sa koneksyon na istabilidad

## Paparating na Malapit

-   Kasalukuyang Ongoing
    -   Siguraduhin ang pagpasok ng teksto sa iOS hindi nagko-clip sa ilalim ng keyboard (katulad ng ginagawa ngayon)
    -   Ayusin ang mga widget sa macOS
    -   Kapain ang iOS na inilabas pilit sa app store
        - Maghintay para sa followup sa paghahabol
    -   Mas mabuting pagsusuri sa iOS at macOS upang subukan kung ang system ay nagre-reconnect at nananatiling konektado sa sumusunod na mga sitwasyon
        - Matapos maghintay ng mahabang panahon
        - Kapag muling pumapasok mula sa background
        - Kapag pinaandar ang TV mula sa OFF na estado
        - Kapag muling nagko-connect sa internet
        - Kapag naglipat ng mga device

-   Susunod: Magdagdag +30 segundo mute timer na may countdown
    -   Huyan ang mute upang i-mute para +30 segundo
    -   mag-Clik ng muli upang alisin ang tahimik at ikansela ito
    -   Ipakita ang isang tagapagpakita sa ilalim ng mute button linya 
        -   Ang Progress bar ay mayroong pahalagahan ng linear progress indicator
        -   Ang Progress bar ay may dalawang mga button: +30 segundo, kanselahin
        -   Ipakita sa ilalim ng pangunahing button panel kaya ito malapit sa mute
    -   Gawin ang +30 na configurable sa 30, 15, 60 segundo na mga opsyon ng mute

-   Hinaharap: Magbigay ng isang optional na Minimalist view sa iOS na gumagaya ng siri remote's view malapitan
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Support visionos gestures din...

## Heneral na Mga Ideya para sa Hinaharap

-   Sumulat ng isang blog post tungkol sa discord bot at ituro sa aking MessageView
    - Gawing mas makasarili ang messageView
-   Sumulat ng isang blog post tungkol sa auto-translation at logic sa paligid nito
-   Sumulat ng isang blog post tungkol sa NWConnection vs URLSession para sa websockets
-   Sumulat ng isang blog post tungkol sa custom keyboard shortcuts
-   Sumulat ng isang blog post tungkol sa ECP Textedit API
-   Sumulat ng isang blog post tungkol sa control center widgets

-   Gumawa ng custom menu bar icon

-   Paano gawin ang voice-to-text o pangkalahatang voice commands?
    - Kailangan baligtarin ang roku voice remote udp protocol
    - O kailangan magdagdag ng custom text-to-speech na may remote button engine?

-   Automate Screenshot Capture

    -   Gamitin ang UITests upang makakuha ng tunay na screenshots para sa lahat ng laki ng device + locales
    -   Gamitin ang AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w upang makakuha ng screenshots sa mga frame
    -   O iba pa
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Subukan ang higit pang mga keyboard hacks para sa iPad
    -   GCKeyboard para sa isa
    -   FocusEnvironment para sa 2
    -   Siguraduhin na ang anumang solusyon ay ginagamit para sa iOS hindi nagbubreak ng pagpapasok ng teksto sa mga mensahe / keyboard na pagpasok

-   UI Tests
    -   Subukan kapag nadagdag ang aparato na ito ay lumilitaw sa device picker at napipili ng roam
    -   Subukang maaaring nag-navigate ang user sa mga setting -> mga device
    -   Subukang maaaring nag-navigate ang user sa mga setting -> mga mensahe
    -   Subukang maaaring nag-navigate ang user sa mga setting -> tungkol
    -   Subukang maaaring i-edit/delete ang user ng mga devices
    -   Subukang maaaring i-click ng user ang mga button kapag naidagdag ang mga aparato
    -   Subukang nakikita ng user ang banner para sa walang mga aparato kapag nagpakita ito
    -   Subukang nakikita ng user ang applinks
    -   Tumukoy sa swiftdat testingmodelcontainer para sa modelcontainers
    -   Tumukoy dito https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para sa kung paano mag-setup ng mga pagsubok

## Mga Pag-Ayos ng Bug

-   Matukoy kung ang loop ng mga tawag sa `nextPacket` ay may sense.
    -   Sa halip na umikot bawat 10ms at umaasa na tama ang timing, dapat ba ako umikot sa mga natanggap na pacet at nagsusubukang iskedyul ito sa host time `10ms * globalSequenceNumber + startHostTime` at sampleTime sa `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Kaya magagamit ko na makalipat mula sa `for await` loop sa orasan sa isang `while !Task.isCancelled` loop na may `Task.sleep` dito.
    -   Okay kaya kailangan namin umikot bawat 10 ms at subukang makuha ang huling packet off at iskedyul ito sa oras na iyon
    -   Tuwing nagkakaroon tayo ng audio sync
        -   Mayroon tayong huling Render Time + isang sync packet
        -   Tinatasa ng packet number na dapat namin ipadala sa + ang sync time
            -   Render Time + karagdagang

## Ipagbawal ang user messaging sa paligid ng pamamahala ng impormasyon / katayuan / capabilities

-   Kapag pinaandar ang aparato gamit ang WOL at hindi nagko-connect pagkatapos ng 5 segundo, o kapag na-power on ang aparato at agad na nabigo, magpakita ng isang mensahe ng babala sa ilalim ng wifi
    -   "Hindi kami nakapag-gising ng inyong Roku" (Alamin ang higit pa) (Huwag na ipakita muli para sa device na ito), (X)
    -   Alamin ang higit pa ipinapakita ang ilang mga dahilan kung bakit
        -   Hindi ka naka-connect sa parehong network (Ipakita ang huling pangalan ng network ng aparato. Tanungin kung ang user ay konektado sa network na ito)
        -   Ang inyong aparato ay nasa malalim na tulog (hindi nakababa kamakailan) at hindi maaaring gisingin
            -   Ang inyong device ay hindi sumusuporta sa WWOL at konektado sa wifi
            -   Ang inyong aparato ay hindi sumusuporta sa WWOL o WOL
        -   Ang iyong network ay hindi setup sa isang paraang nagpapahintulot sa amin na padala ang mga utos ng pag-gising sa aparato
-   Kapag kumiklik sa isang hindi aktibong button, ipinapakita ang abiso na nagpapakita kung bakit ito ay hindi aktibo
    -   Ipakita ang isang tagapagpakita ng impormasyon sa button na nagpapakita na ang impormasyon ay maaaring matanggap kapag ito ay kumiklik?
    -   Mode ng Headphones na hindi pinagana -> dahil hindi sumusuporta ang aparato sa mode ng Headphones sa app na ito
    -   Volume control na hindi pinagana -> dahil ang audio ay naglalabas sa HDMI na hindi sumusuporta sa kontrol ng volume?
-   Kapag aktibong nag-scan para sa mga aparato at walang natagpuan na bagong mga ito, ipakita ang isang mensahe ng babala sa ilalim ng listahan ng aparato
    -   "Hindi kami nakapag-gising ng inyong Roku" (Alamin kung bakit), (X)
    -   Hanapin ang higit pa na nagpapakita ng isang popup na may ilang mga dahilan kung bakit maaaring mangyari ito
        -   Siguraduhin na ang iyong aparato ay nakabukas at konektado sa parehong wifi network ng inyong app. Kung ito ay hindi pa rin gumagana, subukang idagdag ang aparato nang manu-mano.
        -   Link https://roam.msd3.io/manually-add-tv.md at https://support.roku.com/article/115001480188 para sa higit pang troubleshooting o pakikipag-usap
-   Magdagdag ng badge para sa supportsWakeOnWLAN at supportsMute

## Upang i-update kapag bumabagsak ang suporta para sa iOS 17/macOS 14 (Pebrero 2026)

-   Pumunta sa paligid at alisin ang mga tag na @available(iOS 18)
-   Gamitin ang preview na mga katangian upang ma-invoke ang sample data sa mga preview
-   SwiftData
    -   Gamitin ang bagong #Index macro para sa mga modelo
    -   Gamitin ang bagong #Unique macro para sa mga modelo
    -   Gamitin ang batch deletion
-   TipKit
    -   Gamitin ang CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
