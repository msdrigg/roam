---
hide_table_of_contents: true
---

# Aktuellste Roam-Arbeiten

# Kommende Roam-Updates


- Hinzugefügte Steuerungselemente: Play, Mute, Lautstärke ändern und Auswahl aus der Kontrollzentrale!

## Roadmap

-   Update der Keyboard-Steuerung zur Unterstützung von ecp-textedit bei `KeyboardEntry`
    -   Tastatur anzeigen, wenn Textbearbeitung geöffnet wird
    -   Tastatur ausblenden, wenn Textbearbeitung geschlossen wird
    -   Sicherstellen, dass Einfügen + Auswählen/Löschen im Textbearbeitungsfeld wie erwartet funktioniert
    -   Aktuelles modifiziertes Textfeld verwenden, wenn `ecp-textedit` nicht unterstützt wird, Standardtextfeld verwenden, wenn es unterstützt wird
    -   Auf macOS, Unterstützung für Einfügen mit cmdP, kopieren/ausschneiden mit cmdX + cmdC
    -   Fällt `ecp-textedit` aus, kehren Sie zum aktuellen Verhalten des Sendens von Tasten zurück
    -   Auf macOS ein unteres Textfeld anzeigen, wenn die Textbearbeitung aktiviert ist
    -   Auf macOS cmd+v und cmd+c und cmd+x zulassen, um vom/zum Puffer zu kopieren

-   +30 Sekunden Stummschalt Timer mit Countdown hinzufügen
    -   Stummschaltung gedrückt halten, um für +30 Sekunden stumm zu schalten
    -   Klicken Sie erneut, um die Stummschaltung aufzuheben und sie abzubrechen
    -   Zeigen Sie einen Indikator unter der Mute-Tastenlinie 
        -   Fortschrittsbalken hat einen linearen Fortschrittsindikator
        -   Fortschrittsbalken hat zwei Tasten: +30 Sekunden, abbrechen
        -   Zeigen Sie unterhalb des Haupttastenfeldes, damit es nahe an Stummschalten ist
    -   Machen Sie die +30 konfigurierbar auf 30, 15, 60 Sekunden Stummschaltoptionen

-   Bereitstellen einer optionalen minimalistischen Ansicht auf iOS, die Siri Fernbedienung's View eng nachbildet
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Unterstützung für visionos Gesten ebenfalls...
    
## Allgemeine zukünftige Ideen

-   Schreiben Sie einen Blog-Beitrag über den Discord-Bot und verweisen Sie auf meine `MessageView`
-   Schreiben Sie einen Blog-Beitrag über die automatische Übersetzung und die Logik dahinter

-   Anpassbare Menüleistensymbole erstellen

-   Wie mache ich Sprach-zu-Text oder allgemeine Sprachbefehle?
    - Muss das Roku-Sprachfernbedienungs-UDP-Protokoll reverse-engineeren
    - Oder muss benutzerdefiniertes Text-zu-Sprach hinzufügen mit Remote-Tasten-Bedienung?

-   Automatisiere Screenshot-Erfassung

    -   Verwenden Sie UITests, um tatsächliche Screenshots zu erhalten
    -   Verwenden Sie AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w, um die Screenshots in die Rahmen zu bekommen
    -   Oder etwas anderes
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Test mehr Tastatur-Hacks
    -   GCKeyboard für einen
    -   FocusEnvironment für zwei
    -   Sicherstellen, dass, was immer Lösung für iOS verwendet wird, die Texteingabe in Messages/Keyboard-Eintrag nicht zerbricht

-   Füge etwas Event-Tracking hinzu, welche Aktionen die Benutzer eigentlich auf ihren Geräten machen (verbinde vielleicht mit Firebase Analyse?)
    -   Verfolgen Sie, wer die minimalistische Ansicht verwendet, welche Aktionen sie machen usw...

## Bug-Fixes

-   Herausfinden, ob die Schleife der Aufrufe zu `nextPacket` Sinn macht.
    -   Anstelle alle 10 ms zyklisch zu schauen und darauf zu hoffen, dass das Timing richtig ist, sollte ich vielleicht fortlaufend über die empfangenen Pakete gehen und versuchen, sie zu der Host-Zeit `10ms * globaleSequenzNummer + startHostZeit` und zur sampleTime `sequenzNummer * Int64(letzteSampleTime.sampleRate)/PaketeProSek + startSampleTime` zu planen?
    -   Dann kann ich von einer `for await` Schleife über die Uhr zu einer `while !Aufgabe.istAbgebrochen` Schleife mit einem `Aufgabe. schlafen` darin wechseln.
    -   Okay, wir müssen also alle 10 ms zyklisch ansetzen und versuchen, das letzte Paket zu ziehen, und dann zu diesem Zeitpunkt planen
    -   Jedes Mal, wenn wir einen Audio-Sync machen:
        -   Wir haben lastRenderTime + ein Synchronisierungspaket
        -   Schätzen Sie die Paketnummer, die wir senden sollten + die Synchronisationszeit
            -   Renderzeit + zusätzliches

## Testen verbessern

-   UI Tests
    -   Testen, wenn ein Gerät hinzugefügt wurde, dass es in der Geräteauswahl angezeigt wird und von Roam ausgewählt wird
    -   Test, dass Benutzer navigieren zu Einstellungen -> Geräte
    -   Test, dass Benutzer navigieren zu Einstellungen -> Nachrichten
    -   Test, dass Benutzer navigieren zu Einstellungen -> Über
    -   Test, dass Benutzer Geräte bearbeiten/löschen können
    -   Test, dass Benutzer Tasten klicken können, sobald Geräte hinzugefügt werden
    -   Test, dass der Benutzer das Banner für "keine Geräte" sieht, wenn es auftaucht
    -   Test, dass der Benutzer AppLinks sieht
    -   Beziehe dich auf swiftdat modelcontainer Prüfungsmodellcontainer für Modellbehälter
    -   Unter dieses link für Einrichten der Tests beziehen: https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad 

## App Clip

-   AppClip
    -   Füge eine "Geteilten Link zu diesem Gerät bekommen" Taste auf Einstellungen -> Gerät hinzu
        -   Alle 1.1 Mio. App-Clip-Codes vorab generieren und Ringorte codieren (0.5GB Speicherplatz)
        -   Machen Sie eine Taste zum "Holen Sie sich einen teilbaren Link zum Gerät!" mit einer Bildvorschau zum App-Clip-Code (Roam-Farbe)
        -   Laden Sie den Code + Link herunter, und konvertieren Sie sie zu PNG auf dem Gerät, wenn der Standort eines Geräts geändert wird
        -   Lassen Sie den Code das Gerät als geteilten Link zu einem Bild öffnen (mit Vorschau!)
    -   Machen Sie auch den tatsächlichen Gerätelink teilbar

## Verbesserung der Nutzerkommunikation rund um Informations-/Statusverwaltung

-   Update der Info-/Statusverwaltung zur besseren Handhabung von volatilen Zuständen
    -   Bei Trennung, Auswahl, Klick auf Tasten, Wechsel in den Vordergrund, App geöffnet -> Wiederholungsschleife bei Trennung starten
    -   Wiederverbindungsschleife ist, exponentiellen Rückzug zu versuchen, fehlschlagende Verbindungen erneut herzustellen (0.5s, doppelt, 10s Rückzug)
    -   Wenn mit dem Gerät verbunden, immer die Netzwerkwarnungen deaktivieren
    -   Wenn versucht wird, sich mit dem Gerät zu verbinden, oder das Gerät einzuschalten, zeigen Sie anstelle des grauen Punkts ein sich drehendes Info-Symbol 
    -   Wenn das Gerät erfolgreich eingeschaltet wurde, zeigen Sie eine Animation beim Übergang von grau -> drehend -> grün
    -   Wenn das Gerät mit WOL eingeschaltet wird und nach 5 Sekunden keine Verbindung hergestellt wird, oder wenn das Gerät eingeschaltet wird und sofort ausfällt, zeigen Sie eine Warnmeldung unter der WLAN-Meldung
        -   „Wir konnten Ihren Roku nicht wecken“ (Mehr erfahren) (Für dieses Gerät nicht mehr anzeigen), (X)
        -   Mehr erfahren zeigt einige Gründe, warum dies geschehen könnte
            -   Sie sind nicht mit demselben Netzwerk verbunden (Zeigen Sie den letzten Gerätenetzwerknamen an. Fragen Sie, ob der Benutzer mit diesem Netzwerk verbunden ist)
            -   Ihr Gerät ist im Tiefschlaf (wurde kürzlich nicht heruntergefahren) und kann nicht geweckt werden
                -   Ihr Gerät unterstützt kein WWOL und ist mit WLAN verbunden
                -   Ihr Gerät unterstützt kein WWOL oder WOL
            -   Ihr Netzwerk ist nicht so eingerichtet, dass wir Aufweckbefehle an das Gerät senden können
    -   Wiederverbindungsloop = Versuch, die Wiederverbindung zu ECP exponentiell rückzuschlagen
        -   Verbinde ECP zuerst
        -   Höre auf notify zweitens
            -   Handhaben Sie +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   Stellen Sie sicher, dass wir jede dieser Anfragen und deren Format bearbeiten können...
        -  Gerätestatus drittens auffrischen
        -  Abfrage-Textbearbeitung-Zustand viertens auffrischen
            -   Aktualisieren Sie den Textedit-Zustand
        -   Aktualisieren Sie die Gerätesymbole fünftens
    -   Bei allen Änderungen nach der Wiederverbindung (durch Benachrichtigung oder was auch immer)
        -   Gerät (gespeichert) und Gerätestatus (flüchtig) aktualisieren
    -   Nach erneutem Verbinden/Trennen, Online-Status in Fernansicht aktualisieren

## Verbesserung der Benutzerkommunikation über Gerätefähigkeiten

-   Benutzerkommunikation aktualisieren, wenn Fehler auftreten können
    -   Bei Klick auf eine deaktivierte Taste, Popover öffnen, um zu zeigen, warum sie deaktiviert ist
        -   Zeige einen Info-Indikator auf der Taste an, um anzuzeigen, dass Informationen erhalten werden können, wenn sie angeklickt wird?
        -   Kopfhörermodus deaktiviert -> weil das Gerät diesen App keinen Kopfhörermodus unterstützt
        -   Lautstärkeregelung deaktiviert -> weil der Ton über HDMI ausgegeben wird, das keine Lautstärkeregelung unterstützt.
    -   Wenn aktiv nach Geräten gesucht wird und keine neuen gefunden werden, zeigen Sie eine Warnmeldung unter der Geräteliste
        -   „Wir konnten Ihren Roku nicht wecken“ (Warum erfahren), (X)
        -   Finden Sie mehr heraus zeigt ein Popup mit einigen Gründen, warum dies passieren könnte
            -   Stellen Sie sicher, dass Ihr Gerät eingeschaltet ist und mit demselben WLAN-Netzwerk wie Ihre App verbunden ist. Wenn dies immer noch nicht funktioniert, versuchen Sie, das Gerät manuell hinzuzufügen.
            -   Verknüpfen Sie https://roam.msd3.io/manually-add-tv.md und https://support.roku.com/article/115001480188 für weitere Fehlerbehebungen oder Chat
-   Badge für supportsWakeOnWLAN und supportsMute hinzufügen

## ECP Textedit Notizen

Keyboard ECP Session-Befehle (Notizen)

```
- {"Anfrage":"Anfrage-Ereignisse","Anfrage-id":"4","param-Ereignisse":"+Sprache-geändert,+Sprache-änderung,+Media-Player-Status-geändert,+Plugin-ui-run,+Plugin-ui-run-Skript,+Plugin-ui-Exit,+Bildschirmschoner-run,+Bildschirmschoner-Exit,+Plugins-geändert,+Sync-vollendet,+Power-Modus-geändert,+Lautstärke-geändert,+Tv-Eingabe-ui-run,+Tv-Eingabe-ui-Exit,+Tv-Kanal-geändert,+Textedit-geöffnet,+Textedit-geändert,+Textedit-geschlossen,+Textedit-geschlossen,+Ecs-Mikrofon-start,+Ecs-Mikrofon-stop,+Geräte-Name-geändert,+Geräte-Ort-geändert,+Audio-Einstellung-geändert,+Audio-Einstellungen-ungültig"}
    - {"Benachrichtigung":"Textedit-geöffnet","param-Maske":"falsch","param-Max-Länge":"75","param-Auswahl-Ende":"0","param-Auswahl-Start":"0","param-Text":"","param-Textedit-id":"12","param-Textedit-Typ":"voll","Zeitstempel":"608939.003"}
- {"Anfrage":"Abfrage-Textedit-Zustand","Anfrage-id":"10"}
    - {"Inhalt-Daten":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","Inhalt-Typ":"Anwendung/json; charset=\"utf-8\"","Antwort":"Abfrage-Textedit-Zustand","Antwort-id":"10","Status":"200","Status-Nachricht":"OK"}
- {"param-Text":"h","param-Textedit-id":"12","Anfrage":"set-Textedit-Text","Anfrage-id":"20"}
    - {"Antwort":"set-Textedit-Text","Antwort-id":"29","Status":"200","Status-Nachricht":"OK"}
```

## Aktualisieren bei Beendigung der Unterstützung von iOS 17/macOS 14 (Feb 2026)

-   Entfernen der @verfügbar(iOS 18) Tags 
-   Verwenden Sie Vorschaueigenschaften, um Beispieldaten in Vorschaufenstern einzufügen
    -   Wie macht man das, wenn iOS 17 noch ein Faktor ist?
    -   Wie benutzt man @Previewable in Vorschauen, wenn iOS 17 noch ein Faktor ist?
-   SwiftData
    -   Verwenden Sie neues #Index Makro für Modelle
    -   Verwenden Sie neues #Unique Makro für Modelle
    -   Verwenden Sie Stapellöschung
-   TipKit
    -   Verwenden Sie CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698