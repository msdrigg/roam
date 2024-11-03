---
hide_table_of_contents: true
---

# Pinakabagong Pagtatrabaho sa Roam

# Paparating na mga Pag-update sa Roam

## Pangkalahatang Mga Pabutihin

-   Isapanahon ang mga pagsasalin para tiyakin na lahat ay 100%
-   Dokumentuhin ang bot ng discord support at baka gayahin ito sa loob ng isang aklatan
-   Gumawa ng pasadyang menu bar icon

-   Paano gumawa ng voice-to-text o mga pangkalahatang voice commands?
    - Kailangang balikan at suriin ang mga Roku voice remote udp protocol
    - O kailangan magdagdag ng pasadyang text-to-speech sa remote button engine?

-   Magdagdag ng +30 segundo mute timer na may countdown
    -   Higpitan ang mute para itigil ang tunog sa loob ng +30 segundo
    -   Mag-click muli para kanselahin ang mute
    -   Magpakita ng isang top bar notification
        -   Ang progress bar ay mayroong isang linear progress indicator
        -   Ang progress bar ay may dalawang mga button: +30 segundo, kanselahin
        -   Ipakita sa ilalim ng pangunahing button panel para malapit ito sa mute
    -   Gawin ang +30 na configurable sa 30, 15, 60 segundo mute options

-   Awtomatikong Madakmat ang Screenshot

    -   Gamitin ang UITests para makakakuha ng aktwal na screenshots
    -   Gamitin ang AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para makuha ang mga screenshots sa mga frame
    -   O ang iba pa
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Subukan ang iba pang mga keyboard hacks
    -   GCKeyboard para sa isa
    -   FocusEnvironment para sa 2
    -   Siguraduhing ang anumang solusyon na ginagamit para sa iOS ay hindi masira ang text entry sa mga message/keyboard entry
    
-   Isakatuparan ang iOS 18 AppIntents
    -   Magdagdag ng control center app intents
        -   Gamitin ang toggle para tumahimik/magpatugtog at mag-on/mag-off
        -   Gamitin ang mga pindutan para sa lahat ng iba pa
        -   Gamitin ang tamang purple shade
        -   Gawing configurable tulad ng widgets
        -   Gawing nagtatrabaho kasama ang action hint
    -   Pagandahin ang pagkakita ni siri/spotlight sa mga nasa loob ng aking app?
        -   Magdagdag ng universal links sa mga device para maituro ni siri ang mga ito?
        -   Tiyakin na gumagana ang semantic search
        -   Isakatuparan ang transferrable sa pamamagitan ng string/codeable para sa aking aplikasyon na mga entity
            -   ProxyRepresentation
            -   CodableRepresentation
-   Magbigay ng isang optional na Minimalist view sa iOS na maaring gayahin ang view ng siri remote
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Suportahan ang mga visionos gestures din ...
    -   Kailangan mabuo muna ang textedit api
-   Magdagdag ng ibang event tracking sa mga ginagawa ng mga gumagamit sa kanilang mga device (I-konekta sa firebase analytics siguro?)
    -   Itala kung sino ang gumagamit ng minimalist view, anong mga aksyon ang ginagawa nila, etc...

## Pag-aayos ng Bug

-   Alamin kung ang loop ng mga tawag sa `nextPacket` ay makatutulong.
    -   Sa halip na umikot bawat 10ms at umaasa na tama ang timing, dapat ba akong mag-ikot sa mga natanggap na mga packet at subukang iskedyul ang mga ito sa oras na `10ms * globalSequenceNumber + startHostTime` at sampleTime sa `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Sa ganitong paraan maaari akong lumipat mula sa isang `for await` na loop sa oras sa isang `while !Task.isCancelled` loop na may kasamang `Task.sleep`.
    -   Okay kaya kailangan nating mag-ikot bawat 10 ms at subukan na kunin ang huling packet at iskedyul ito sa oras na yon
    -   Tuwing ginagawa namin ang audio sync
        -   Mayroon tayong lastRenderTime + a sync packet
        -   Tantiyahan ang bilang ng packet na dapat nating ipadala at + ang oras ng sync
            -   Render Time + dagdag

## Pabutihin ang Testing

-   UI Tests
    -   Test kung ang device ay nadagdag na ito ay lumalabas sa device picker at pinili ng roam
    -   Test na ang user ay makakapunta sa settings -> devices
    -   Test na ang user ay makakapunta sa settings -> messages
    -   Test na ang user ay makakapunta sa settings -> about
    -   Test na ang user ay makakapag-edit/delete ng mga device
    -   Test na ang user ay makakapindot ng mga button kapag naidagdag na ang mga device
    -   Test na ang user ang banner para sa walang mga device kapag ito ay lumalabas
    -   Test na nakikita ng user ang applinks
    -   Tumukoy sa swiftdat testingmodelcontainer para modelcontainers
    -   Tumukoy dito https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para sa kung paano i-set up ang mga test

## App Clip

-   AppClip
    -   Magdagdag ng "getAShareableLinkToThisDevice" na button sa settings -> device
        -   Pre-generate lahat ng 1.1M app clip codes at i-encode ang mga lokasyon ng ring (0.5GB)
        -   Gumawa ng button na "Kunin ang shareable link sa device!" na may image preview sa app clip code (kulay ng roam)
        -   I-download ang code + link at i-convert sa PNG sa device kapag ang lokasyon ng device ay nabago
        -   Buksan ang code upang makita ang device bilang isang shared link sa isang larawan (may preview!)
    -   Gawin rin na maaaring i-share ang aktwal na link sa device 

## Pabutihin ang user messaging patungkol sa info/status management

-   I-update ang Info/status management para mas maayos na ma-handle ang hindi tiyak na kalagayan
    -   Kapag na-disconnect, napili, napindot ang button, lumipat sa unahan, binuksan ang app -> Muling simulan ang reconnect loop kung na-disconnect
    -   Ang reconnect loop ay upang ma-eksponensyal na backup patungan ang nagfa-fail na mga koneksyon (0.5s, doble, 10s backoff)
    -   Kapag nakakonekta sa device, palaging i-disable ang mga babala ng network
    -   Kung sinusubukan kumonekta sa device, o sinusubukang mag-on sa device, magpakita ng ikot na impormasyon na icon sa halip na gray dot
    -   Kapag nag-on sa device at nagtagumpay, magpakita ng isang animasyon sa transisyon mula gray -> ikot -> luntian
    -   Kung nag-on sa device gamit ang WOL at hindi nakakonekta pagkaraan ng 5 segundo, o kung nag-on ang device at agad na nabigo, magpakita ng isang babala sa ilalim ng wifi
        -   "Hindi namin nagawang magising ang iyong Roku" (Alamin pa), (Huwag ng ipakita muli para sa device na ito), (X)
        -   Alamin pa ipapakita ang ilang mga dahilan kung bakit
            -   Hindi ka nakakonekta sa parehong network (Ipakita ang huling pangalan ng network ng device. Itanong kung naka-konekta ang user sa network na ito)
            -   Ang iyong device ay nasa malalim na tulog (hindi kamakailan naputol) at hindi maaring magising
                -   Ang iyong device hindi sumusuporta sa WWOL at nakakonekta sa wifi
                -   Ang iyong device hindi sumusuporta sa WWOL o WOL
            -   Hindi na-set up ang iyong network para maipadala namin ang mga utos na gisingin ang device
    -   Reconnect loop = Eksponentiyal na pagtatangkang muli na kumonekta sa reconnect ECP
        -   Reconnect ECP una
        -   Makinig sa notify pangalawa
            -   Hwgat +power-mode-changed, +textedit-opened, +textedit-tingi, +textedit-closed, +device-name-changed
            -   Siguraduhin na ma-handle namin ang bawat isang mga request na ito at ang kanilang format…
        -   Mag-refresh ng state ng device pangatlo
        -   Mag-refresh ng query-textedit-state pang-apat
            -   I-update ang state ng textedit
        -   Mag-refresh ng mga icon ng device pang-lima
    -   Sa lahat ng mga pagbabago pagkatapos mag-reconnect (sa pamamagitan ng notify o anuman)
        -   I-update ang Device (nakaimbak) at DeviceState (volatile)
    -   Pagkatapos ng pagka-reconnect/disconnect, mag-update ng online status sa remote view

## Improve user messaging around device capabilities

-   Mag-update ng user messaging kapag ang mga error ay maaring mangyari
    -   Kapag pinindot ang isang hindi gumaganang button, buksan ang popover upang ipakita kung bakit ito na-disable
        -   Ipakita ang info indicator sa button para ipahiwatig na ang impormasyon ay tatanggapin kapag pinindot ito?
        -   Ang mode ng Headphones ay na-ban -> dahil ang device ay hindi sumusuporta sa mode ng headphones sa app na ito
        -   Ang kontrol ng Volume ay na-disable -> dahil ang audio ay outputting sa HDMI na hindi sumusuporta sa kontrol ng volume?
    -   Kapag aktibong nag-scan para sa mga device at wala pang natagpuan na mga bagong, magpakita ng isang babala sa ilalim ng listahan ng device
        -   "Hindi namin nagawang gumising sa iyong Roku" (Alamin kung bakit), (X)
        -   Alamin pa magpapakita ng pop-up na may ilang mga dahilan kung bakit nangyayari ito
            -   Siguraduhing nakasindi ang iyong device at konektado sa parehong wifi network na mayroon ang iyong app. Kung hindi pa rin gumagana, subukang magdagdag ng device ng manu-mano.
            -   Link https://roam.msd3.io/manually-add-tv.md and https://support.roku.com/article/115001480188 para sa iba pang troubleshooting o chat
-   Magdagdag ng badge para sa supportsWakeOnWLAN at supportsMute

## Suportahan ang ecp textedit

-   I-update ang manipulasyon ng keyboard upang suportahan ang ecp-textedit sa `KeyboardEntry`
    -   Ipakita ang keyboard kapag ang textedit ay binuksan
    -   Itago ang keyboard kapag ang textedit ay kinansela
    -   Test na ang pagdikit + select/delete sa textedit field ay gumagana tulad ng inaasahan
    -   Kung sinusuportahan ang ecp-textedit, payagan ang pagpili, ang pagkuha ng teksto at ang paglipat ng cursor. Padala lamang ng muli ng tekstong bawat oras na ito ay nagbabago kung ito ay sinusuportahan.
    -   Kung hindi sinusuportahan ang ecp-textedit, ibalik muna ang kasalukuyang pag-uugali ng pagpindot ng mga key
    -   Sa MacOS ipakita ang isang indicator kapag ang textedit ay pinagana
    -   Ang MacOS ay nagpapahintulot na cmd+v at cmd+c at cmd+x upang copy paste mula/sa buffer

Mga Command ng Keyboard ECP Session (mga tala)
   
```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Ia-update kapag itinigil ang suporta para sa iOS 17/macOS 15 (2025)

-   Gamitin ang mga trait ng naunang tanaw para mag-inject ng sample data sa mga naunang tanaw
    -   Paano gawin ito kung ang iOS 17 ay mayroon pa rin mga factor?
    -   Paano gamitin ang @Previewable sa mga naunang tanaw kung ang iOS 17 ay mayroon pa rin mga factor??
-   SwiftData
    -   Gamitin ang bagong #Index macro para sa mga model
    -   Gamitin ang bagong #Unique macro para sa mga model
    -   Gumamit ng batch deletion
-   TipKit
    -   Gumamit ng CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
