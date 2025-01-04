---
hide_table_of_contents: true
---

# Roam Roadmap

## Kumparbeit ng Ginagawa para sa Susunod na Update

-   Nagdagdag ng mga kontrol widget: Maglaro, I-mute, Palitan ang Volume at Pumili mula sa Control center!
-   Nagdagdag ng mas mahusay na paghawak sa text field para sa maraming roku apps
    -   Awtomatikong buksan ang text field kapag ang tekstong pag-edit ay magagamit
    -   Kopyahin, Putulin, Paste mula sa macOS (gamit ang keyboard)
    -   Kopyahin, Putulin, Paste + Generalized edit sa iOS
-   Mas mahusay na pag-uulat tungkol sa mga pahintulot sa lokal na network at connectivity
-   Itinaguyod na keyboard functionality
-   Itinaguyod na mga pagbabago sa koneksyon

## Darating na

-   Magdagdag ng pagpipiliang long-press sa mga susi
    -   Long-press sa right arrow upang ff
    -   Long-press sa left arrow upang rr
    -   Long-press mute upang long-mute
        -   Gawing configurable ang +30 hanggang 30, 15, 60 segundo mute na mga pagpipilian
        -   Ipakita ang banner na may +30 sec, x upang kanselahin, indikasyon ng linearyang progreso sa background
            -   Ipakita sa ilalim ng pangunahing panel ng pindutan upang malapit ito sa tahimik
        -   Nagkakansela kapag natahimik muli (at gumagawa rin ng api call)
-   Ayusin ang macOS widgets

-   Hinaharap: Magbigay ng kusang minimalistang view sa iOS na malapitang nagpapalitaw ng tingin sa siri remote
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Suportahan din ang visionos gestures...

## Pangkalahatang Ideya para sa Hinaharap

-   Gumawa ng mga pasadyang icon sa menu bar

-   Paano gumawa ng voice-to-text o mga pangkalahatang utos na pagsasalita?

    -   Kailangan maibalik-inhinyero ang roku voice remote udp protocol
    -   O kailangan magdagdag ng pasadayang text-to-speech gamit ang remote button engine?

-   Automatize ang Pagtangkap ng Screenshot

    -   Gamitin ang UITests upang makakuha ng tunay na mga screenshot para sa lahat ng mga sukat ng device + mga lokal
    -   Gamitin ang AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w upang makuha ang mga screenshot sa mga frame
    -   O iba pa
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Subukan ang mas marami pang mga keyboard hack sa iPad

    -   GCKeyboard para sa isa
    -   FocusEnvironment para sa 2
    -   Siguraduhin na kung ano man ang solusyong ginamit para sa iOS ay di nasira ang pagpasok ng text sa mga mensahe/pagpasok ng keyboard

-   UI Tests
    -   I-test kapag ang device ay idinagdag na lumalabas ito sa device picker at pinili ng roam
    -   I-test na navigasyon ng user sa settings -> mga device
    -   I-test na navigasyon ng user sa settings -> mga mensahe
    -   I-test na navigasyon ng user sa settings -> tungkol
    -   I-test na mag-edit/ tanggalin ng mga user ang mga device
    -   I-test na mag-click ng mga pindutan ng user kapag ang mga device ay idinagdag
    -   I-test na napapansin ng user ang banner para sa walang mga device kapag ito ay lumalabas
    -   I-test na ang user ay nakakita ng mga applinks
    -   Sumangguni sa swiftdat testingmodelcontainer para sa mga modelcontainers
    -   Sumangguni dito https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para sa kung paano i-setup ang mga test

## Mga Patch ng Bug

-   Malaman kung ang loop ng tawag sa `nextPacket` ay may sentido.
    -   Sa halip na mag-looping bawat 10ms at umaasang tama ang timing, dapat ba akong mag-looping sa mga natanggap na packets at sinusubukang iskedyul ang mga ito sa host time na `10ms * globalSequenceNumber + startHostTime` at sampleTime sa `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Maaari kong palitan mula sa `for await` loop sa clock na `while !Task.isCancelled` loop na may `Task.sleep` sa loob nito.
    -   Kaya kailangan namin mag-loop bawat 10 ms at subukang kunin ang huling packet at iskedyul ito sa panahong iyon
    -   Tuwing gumagawa kami ng audio sync
        -   Mayroon kaming lastRenderTime + a sync packet
        -   Tantiyahin ang bilang ng packet na dapat nating ipadala sa + ang sync time
            -   Render Time + additional

## Ipataguyod ang pagmamensahe ng user tungkol sa pamamahala ng info/status/capabilities

-   Kapag pinapataas ang device gamit ang WOL at hindi nakakonekta pagkatapos ng 5 segundo, o kapag pinapataas ang device at agad na nabigo, magpakita ng babala sa ilalim ng wifi isa
    -   “Hindi kami nakapagpatulog sa iyong Roku” (Alamin ang higit pa) (Wag na ipakita muli para sa device na ito), (X)
    -   Alamin ang higit pa na nagpapakita ng ilang mga dahilan kung bakit
        -   Hindi ka nakakonekta sa parehas network (Ipakita ang huling pangalan ng network ng device. Tanungin kung ang user ay nakakonekta sa network na ito)
        -   Ang iyong device ay malalim na natutulog (hindi kamakailan pinatay) at hindi maaring gisingin
            -   Ang iyong device ay hindi sumusuporta sa WWOL at nakakonekta sa wifi
            -   Ang iyong device ay hindi sumusuporta sa WWOL o WOL
        -   Ang iyong network ay hindi nai-setup sa paraan upang payagan kami na magpadala ng mga utos na gising sa device
-   Kapag pinindot ang isang hindi pinagana na button, ipakita ang notipikasyon na nagpapahiwatig kung bakit ito ay hindi pinagana
    -   Magpakita ng indicator na impormasyon sa button upang ipahiwatig na ang impormasyon ay maaaring matanggap kapag ito ay pinindot?
    -   Headphones mode ay hindi pinagana -> dahil ang device ay hindi sumusuporta sa headphone mode para sa app na ito
    -   Kontrol sa volume ang hindi pinagana -> dahil ang audio ay nag-aoutput sa pamamagitan ng HDMI na hindi sumusuporta sa mga kontrol sa volume?
-   Kapag aktibong gumaganap para sa mga device at walang bagong natagpuan na magpakita ng babala sa ilalim ng listahan ng device
    -   “Hindi kami nakapagpatulog sa iyong Roku” (Alamin kung bakit), (X)
    -   Alamin kung bakit ipapakita ang isang popup na may ilang mga dahilan kung bakit nangyayari ito
        -   Siguraduhing ang iyong device ay naka-on at nakakonekta sa parehong wifi network ng iyong app. Kung hindi pa rin ito gumagana, subukang idagdag ang device nang manu-mano.
        -   Link https://roam.msd3.io/manually-add-tv.md at https://support.roku.com/article/115001480188 para sa higit pang troubleshooting o chat
-   Magdagdag ng badge para sa supportsWakeOnWLAN at supportsAudioControls

## Upang ma-update kapag nokoksan ng suporta para sa iOS 17/macOS 14 (Pebrero 2026)

-   Ikutin at alisin ang @available(iOS 18) tags
-   Gamitin ang preview traits upang maglagay ng sample data sa mga preview
-   SwiftData
    -   Gamitin ang bagong #Index macro para sa mga modelo
    -   Gamitin ang bagong #Unique macro para sa mga modelo
    -   Gamitin ang batch na pagbubura
-   TipKit
    -   Gamitin ang CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
