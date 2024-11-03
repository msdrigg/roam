---
hide_table_of_contents: true
---

# Ang pinaka-kamakailan na trabaho sa roam

# Ang mga darating na Roam Updates

- Nagdagdag ng kontrol na mga widget: Play, Mute, Change Volume at Select from Control center!

## Roadmap

- I-update ang paghawak ng keyboard upang suportahan ang ecp-textedit sa `KeyboardEntry`
    - Ipakita ang keyboard kapag binuksan ang textedit
    - Itago ang keyboard kapag naisara ang textedit
    - Siguraduhin na gumagana ang pag-paste + select/delete sa field ng textedit
    - Gamitin ang kasalukuyang binagong textfield kung hindi suportado ang ecp-textedit, gamitin ang standard na textfield kung ito ay
    - Sa macOS, suportahan ang paste kasama ang cmdP, copy/cut kasama ang cmdX + cmdC
    - Kung hindi suportado ang ecp-textedit, bumalik sa kasalukuyang ugali ng pagpapadala ng mga key
    - Sa mga macOS ipakita ang ibabang text field kapag pinagana ang textedit 
    - Sa mga macOS payagan ang cmd+v at cmd+c at cmd+x para mag-kopya paste mula/sa buffer

- Magdagdag ng +30 segundo mute timer kasama ang bilang pababa
    - Higitan ang mute para i-mute ng +30 segundo
    - Mag-click muli upang hindi i-mute at kanselahin ito
    - Ipakita ang isang tagapagpahiwatig sa ibaba ng linya ng mute button
        - Ang progress bar ay may linear na tagapagsulong ng tagapagsulong
        - May dalawang button ang progress bar: +30 segundo, kanselahin
        - Ipakita sa ibaba ng pangunahing panel ng button para malapit ito sa mute
    - Gawin ang +30 maaaring i-configure sa 30, 15, 60 segundo na mga opsyon ng mute

- Magbigay ng isang opsyonal na Minimalist view sa iOS na gayahin nang malapit ang view ng siri remote
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Sumusuporta din sa mga gesture ng visionos...

## Pangkalahatang Mga Ideya sa Hinaharap

- Sumulat ng isang blog post tungkol sa discord bot at ituro ang aking MessageView
- Sumulat ng isang blog post tungkol sa auto-translation at logic sa paligid niyon

- Gumawa ng pasadyang icon ng menu bar

- Paano gawin ang voice-to-text o pangkalahatang mga utos ng boses?
    - Kailangan reverse-engineer ang protocol ng roku voice remote udp
    - O kailangan magdagdag ng pasadyang teksto-sa-talumpati sa remote button engine?

- Automatikong Screenshot Capture

    - Gamitin ang UITests upang makakuha ng aktwal na screenshots
    - Gamitin ang AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w upang makuha ang mga screenshot sa mga frame
    - O ibang bagay
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/templates/s/iphone/

- Subukan ang mga hack ng keyboard
    - GCKeyboard para sa isa
    - FocusEnvironment para sa 2
    - Tiyakin na anuman ang solusyon na ginagamit para sa iOS hindi sinira ang pagpasok ng teksto sa mga mensahe / keyboard entry

- Magdagdag ng ilang pagsubaybay sa kaganapan sa kung ano ang mga aksyon na tunay na ginagawa ng mga gumagamit sa kanilang mga device (kumonekta sa firebase analytics maybe?)
    - Subaybayan kung sino ang gumagamit ng minimalist view, kung ano ang mga aksyon na ginagawa nila, atbp...

## Ayusin ang mga error

- Alamin kung ang loop ng mga tawag sa `nextPacket` ay may sentido.
    - Sa halip na mag-loop sa bawat 10ms at umaasa na tama ang oras, dapat ba akong mag-loop sa natanggap na mga packet at sinusubukan na iskedyul ang mga ito sa host time `10ms * globalSequenceNumber + startHostTime` at sampleTime sa `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    - Kaya kailangan kong mag-loop sa bawat 10 ms at subukan na kunin ang huling packet at pagtapos iskedyul ito sa panahon na iyon
    - Tuwing gumagawa kami ng audio sync
        - Mayroon tayong huling Render Time + isang sync na packet
        - Tinataya ang bilang ng packet na dapat nating ipadala sa + ang oras ng sync
            - Oras ng Render + karagdagang

## Pagpapabuti ng Testing

-   UI Tests
    -   Subukan kapag nadagdag ang device na ito ay lumilitaw sa picker ng device at pinili ng roam
    -   Subukan na ang user ay maaaring nag-navigate sa mga setting -> devices
    -   Subukan na ang user ay maaaring nag-navigate sa mga setting -> messages
    -   Subukan na ang user ay maaaring nag-navigate sa mga setting -> about
    -   Subukan na ang user ay maaaring i-edit/delete devices
    -   Subukan na ang user ay maaaring mag-click ng mga button kapag ang mga device ay idinagdag
    -   Subukan na ang user nakakita ng banner para sa walang mga device kapag ito ay nagpakita
    -   Subukan na ang user nakakita ng applinks
    -   Tumukoy sa swiftdat testingmodelcontainer para sa modelcontainers
    -   Tumukoy dito https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para sa kung paano mag-setup ng mga test

## App Clip

-   AppClip
    -   Magdagdag ng isang "getAShareableLinkToThisDevice" button sa settings -> device
        - Pre-generate lahat ng 1.1M app clip codes at i-encode ang mga lokasyon ng ring (0.5GB)
        - Gumawa ng isang button upang "Makakuha ng isang shareable link sa device!" kasama ang isang image preview sa app clip code (kulay ng roam)
        - I-download ang code + link at i-convert sa PNG sa device kapag binago ang lokasyon ng device
        - Magkaroon ng code upang buksan ang device bilang isang shared link sa isang imahe (kasama ang preview!)
    - Gumawa rin ng aktwal na link ng device na shareable

## Pagpapabuti ng user messaging hinggil sa pamamahala ng info/status

-   I-update ang pagmamaneho ng Info/status upang mas mahusay na hawakan ang mabagsik na estado
    - Sa diskonekta, piliin, i-click ang button, ilipat sa harap, buksan ang app -> Muling simulan ang loop ng muling konekta kung naka-diskonekta
    - Ang loop ng muling konekta ay upang ma-xponensiyal na gumalaw sa muling pagtatangkang muling magkonekta ng nabibigong mga koneksyon (0.5s, double, 10s backoff)
    - Kapag nakakonekta sa device, palaging huwag paganahin ang mga babala sa network
    - Kapag sinusubukan ma-konekta sa device, o sinusubukang isapang-enerhiya ang device, ipakita ang naglalaro ng impormasyong icon sa halip na gray dot
    - Kapag nag-power on sa device at nagtagumpay, ipakita ang animation sa transition mula sa gray -> naglalaro -> berde
    - Kapag nag-power on sa device na may WOL at hindi konektado pagkatapos ng 5 segundo, o kapag nag-power on ang device at agad na nabigo, ipakita ang isang babala ng mensahe sa ilalim ng isa sa wifi
        - “Hindi kami nakapag-gising sa inyong Roku” (Malaman pa nang higit) (Huwag nang ipakita muli para sa device na ito), (X)
        - Magpakita ng iba pang dahilan kung bakit
            - Hindi ka konektado sa parehong network (Ipakita ang huling pangalan ng network ng device. Itanong kung ang user ay konektado sa network na ito)
            - Ang iyong device ay nasa malalim na pagtulog (hindi kamakailan binabaan ng kapangyarihan) at hindi nagigising
                - Ang iyong device ay hindi sumusuporta sa WWOL at konektado sa wifi
                - Ang iyong device ay hindi sumusuporta sa WWOL o WOL
            - Ang iyong network ay hindi itinakda sa isang paraan upang payagan kami na magpadala ng mga utos ng paggising sa device
    - Reconnect loop = Umurong ng Exponential na pagtatangkang muling magkonekta sa reconnect ECP
        - Muling nagkakonekta sa ECP muna
        - Mga notify sa pangalawa
            - Hantei +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            - Siguraduhin na maaari nating hawakan ang bawat isa sa mga kahilingang ito at ang kanilang format...
        - I-refresh ang estado ng device sa pangatlo
        - I-refresh ang query-textedit-state sa pang-apat
            - I-update ang estado ng textedit
        - I-refresh ang mga icon ng panglimang device
    - Sa lahat ng mga pagbabago pagkatapos muling magkonekta (sa pamamagitan ng pag-abiso o anuman)
        - I-update ang Device (naimbakan) at DeviceState (voilatile)
    - Pagkatapos muling magkonekta/ma-diskonekta, i-update ang online status sa remote view

## Pagpapabuti ng user messaging hinggil sa mga kakayahan ng device

-   I-update ang mga mensaheng user kapag maaaring mangyari ang mga error
    -   Kapag nag-click sa isang hindi pinagana na button, buksan ang popover upang ipakita kung bakit ito ay hindi pinagana
        -   Ipakita ang isang impormasyon na indikator sa button upang ipahiwatig na maaaring matanggap ang impormasyon kapag ito ay na-click?
        -   Ang mode ng Headphones ay hindi pinagana -> dahil hindi sumusuporta ang device sa mode ng headphones sa app na ito
        -   Ang kontrol ng volume ay hindi pinagana -> dahil ang audio ay nag-ooutput sa HDMI na hindi sumusuporta sa mga kontrol ng volume?
    -   Kapag aktibong sinusuri para sa mga device at walang natagpuan na mga bago ipakita ang isang babala ng mensahe sa ibaba ng listahan ng device
        -   “Hindi kami nakapag-gising sa inyong Roku” (Malaman kung bakit), (X)
        -   Magpakita ng higit pang mga pagpapakita ng isang popup na may ilang mga dahilan kung bakit ito ay maaaring nangyari
            -   Siguraduhin ang inyon device ay powered on at nakakonekta sa parehong wifi network bilang ang inyong app. Kung hindi pa rin ito gumagana, subukan itong idagdag nang manu-mano.
            -   Link https://roam.msd3.io/manually-add-tv.md at https://support.roku.com/article/115001480188 para sa higit na paglulutas ng problema o chat
-   Magdagdag ng badge para sa supportsWakeOnWLAN at supportsMute

## Mga Tala sa Teksto ng ECP

Mga utos ng Keyboard ECP Session (mga note)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Para i-update kapag bumabagsak ang suporta para sa iOS 17/macOS 14 (Feb 2026)

-   Maglibot at alisin ang tatak ng @available(iOS 18)
-   Gumamit ng mga katangian ng preview para ipasok ang halimbawa ng data sa mga preview
    -   Paano gawin ito habang ang iOS 17 ay kasalukuyang isang factor?
    -   Paano gagamitin ang @Previewable sa mga preview habang ang iOS 17 ay kasalukuyang isang factor??
-   SwiftData
    -   Gamitin ang bagong #Index macro para sa mga modelo
    -   Gamitin ang bagong #Unique macro para sa mga modelo
    -   Gamitin ang pagsasawang pagtatanggal
-   TipKit
    -   Gamitin ang CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698

