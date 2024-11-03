---
hide_table_of_contents: true
---

# Neueste Roam-Arbeiten

# Kommende Roam-Aktualisierungen

## Allgemeine Verbesserungen

-   Aktualisieren Sie die Übersetzungen, um sicherzustellen, dass alle bei 100% sind
-   Dokumentieren Sie den Discord-Support-Bot und duplizieren Sie ihn möglicherweise in eine Bibliothek
-   Erstellen Sie ein benutzerdefiniertes Menüleisten-Symbol

-   Wie führt man Sprache-zu-Text oder allgemeine Sprachbefehle aus?
    - Notwendigkeit zur Rückentwicklung des Sprachfernbedienungs-UDP-Protokolls von Roku
    - Oder Notwendigkeit zur Hinzufügung von benutzerdefiniertem Text-zu-Sprache mit Fernbedienungsbutton-Engine?

-   Fügen Sie einen +30 Sekunden Stummschalttimer mit Countdown hinzu
    -   Halten Sie Stumm, um für +30 Sekunden stummzuschalten
    -   Klicken Sie erneut, um Stummschalten abzubrechen
    -   Zeigen Sie eine Benachrichtigung in der oberen Leiste
        -   Fortschrittsbalken hat einen linearen Fortschrittsindikator
        -   Fortschrittsbalken hat zwei Tasten: +30 Sekunden, Abbrechen
        -   Zeigen Sie unterhalb des Hauptknopfpanels, damit es in der Nähe von Stumm ist
    -   Machen Sie das +30 konfigurierbar auf 30, 15, 60 Sekunden Stummschalt-Optionen

-   Automatisieren Sie die Screenshot-Erfassung

    -   Verwenden Sie UITests, um tatsächliche Screenshots zu erhalten
    -   Verwenden Sie AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w um die Screenshots in den Frames zu erhalten
    -   Oder etwas anderes
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Testen Sie weitere Tastatur-Hacks
    -   GCKeyboard für eins
    -   FocusEnvironment für 2
    -   Stellen Sie sicher, dass egal welche Lösung für iOS verwendet wird, die Texteingabe in Nachrichten/Tastatureingaben nicht beeinträchtigt wird
    
-   Implementieren Sie iOS 18 AppIntents
    -   Fügen Sie Kontrollzentrums-App-Intents hinzu
        -   Verwenden Sie Umschalten für Stummschalten/Stummschaltung aufheben und Ein/Aus
        -   Verwenden Sie Tasten für alles andere
        -   Verwenden Sie den korrekt getönten Lila
        -   Machen Sie es konfigurierbar wie Widgets
        -   Lassen Sie es mit Aktionshinweis arbeiten
    -   Lassen Sie siri/spotlight besser die Dinge in meiner App irgendwie sehen?
        -   Fügen Sie universelle Links zu den Geräten hinzu, so dass siri sie verlinken kann?
        -   Stellen Sie sicher, dass die semantische Suche funktioniert
        -   Implementieren Sie übertragbare über String/Codeable für meine App-Entitäten
            -   ProxyDarstellung
            -   CodableDarstellung
-   Bieten Sie eine optionale minimalistische Ansicht auf iOS an, die die Ansicht von siri remote genau nachahmt
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Unterstützen Sie auch die Visionos-Gesten...
    -   Muss zuerst die Textedit-API erstellen
-   Fügen Sie ein Ereignis-Tracking hinzu, welche Aktionen die Benutzer tatsächlich auf ihren Geräten durchführen (Verbindung zu Firebase-Analyse vielleicht?)
    -   Verfolgen Sie, wer die minimalistische Ansicht benutzt, welche Aktionen sie durchführen, usw...

## Fehlerbehebungen

-   Finden Sie heraus, ob die Schleife von Anrufen an `nextPacket` Sinn macht.
    -   Statt alle 10ms zu schleifen und zu hoffen, dass das Timing korrekt ist, sollte ich stattdessen über empfangene Pakete schleifen und versuchen, sie zur Hostzeit `10ms * globalSequenceNumber + startHostTime` und Samplezeit zu `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime` zu planen?
    -   Dann kann ich von einer `for await` Schleife über die Uhr zu einer `while !Task.isCancelled` Schleife mit einem `Task.sleep` darin wechseln.
    -   Also müssen wir alle 10 ms schleifen und versuchen, das letzte Paket abzuziehen und dann zu dieser Zeit zu planen
    -   Immer wenn wir einen Audiosync durchführen
        -   Wir haben die letzte Wiedergabezeit + ein Synchronisierungspaket
        -   Schätzen Sie die Paketnummer, die wir aussenden sollten, + die Synchronisationszeit
            -   Wiedergabezeit + zusätzlich

## Testverbesserung

-   UI-Tests
    -   Testen Sie, ob das Gerät, wenn es hinzugefügt wird, im Gerätepicker angezeigt wird und von Roam ausgewählt wird
    -   Testen Sie, ob der Benutzer zu Einstellungen -> Geräten navigieren kann
    -   Testen Sie, ob der Benutzer zu Einstellungen -> Nachrichten navigieren kann
    -   Testen Sie, ob der Benutzer zu Einstellungen -> Über navigieren kann
    -   Testen Sie, ob der Benutzer Geräte bearbeiten/löschen kann
    -   Testen Sie, ob der Benutzer Tasten drücken kann, sobald Geräte hinzugefügt sind
    -   Testen Sie, ob der Benutzer ein Banner für keine Geräte sieht, wenn es auftaucht
    -   Überprüfen Sie, ob der Benutzer Applinks sieht
    -   Beziehen Sie sich auf Swiftdat Testingmodelcontainer für Modelcontainers
    -   Beziehen Sie sich hier https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad darauf, wie Tests eingerichtet werden

## App Clip

-   AppClip
    -   Fügen Sie eine "getAShareableLinkToThisDevice" Taste auf Einstellungen -> Gerät hinzu
        -   Generieren Sie alle 1.1M App-Clip-Codes vor und kodieren Sie die Ringpositionen (0.5GB)
        -   Erstellen Sie eine Taste "Erhalten Sie einen teilbaren Link zum Gerät!" mit einer Bildvorschau auf den App-Clip-Code (Roam-Farbe)
        -   Laden Sie den Code + den Link herunter und konvertieren Sie ihn auf dem Gerät zu PNG, wenn eine Geräteposition geändert wird
        -   Lassen Sie den Code das Gerät als einen geteilten Link zu einem Bild (mit Vorschau!) öffnen
    -   Machen Sie auch den eigentlichen Gerätelink teilbar

## Verbesserung der Benutzernachrichten rund um Informations-/Statusverwaltung

-   Aktualisieren Sie die Informations-/Statusverwaltung, um den flüchtigen Zustand besser zu handhaben
    -   Beim Trennen der Verbindung, Auswählen, Klicken auf einen Button, Verschieben in den Vordergrund, App geöffnet -> Starten Sie die Wiederverbindungs-Schleife neu, wenn getrennt
    -   Die Wiederverbindungs-Schleife besteht darin, im exponentiellen Backoff fehlgeschlagene Verbindungen erneut zu versuchen (0.5s, verdoppeln, 10s Backoff)
    -   Wenn mit dem Gerät verbunden, deaktivieren Sie immer die Netzwerkwarnungen
    -   Wenn Sie versuchen, eine Verbindung zum Gerät herzustellen, oder versuchen, das Gerät einzuschalten, zeigen Sie anstelle des grauen Punkts ein rotierendes Informations-Icon an
    -   Wenn das Einschalten des Geräts gelingt, zeigen Sie eine Animation beim Übergang von grau -> rotierend -> grün
    -   Wenn das Gerät mit WOL eingeschaltet wird und nach 5 Sekunden keine Verbindung hergestellt wird, oder wenn das Gerät eingeschaltet wird und sofort ein Fehler auftritt, zeigen Sie eine Warnmeldung unterhalb der Wifi-Nachricht
        -   “Wir konnten Ihren Roku nicht wecken” (Mehr erfahren) (Nicht mehr für dieses Gerät anzeigen), (X)
        -   Mehr erfahren zeigt einige Gründe, warum dies so ist
            -   Sie sind nicht mit demselben Netzwerk verbunden (Zeigen Sie den letzten Gerätenetzwerknamen an. Fragen Sie, ob der Benutzer mit diesem Netzwerk verbunden ist)
            -   Ihr Gerät ist im Tiefschlaf (wurde kürzlich nicht heruntergefahren) und kann nicht aufgeweckt werden
                -   Ihr Gerät unterstützt WWOL nicht und ist mit dem Wifi verbunden
                -   Ihr Gerät unterstützt WWOL oder WOL nicht
            -   Ihr Netzwerk ist nicht so eingerichtet, dass wir Aufwachbefehle an das Gerät senden können
    -   Wiederverbindungs-Schleife = exponentiell zurückstellend versuchen, die ECP wiederzuverbinden
        -   Verbinden Sie ECP zuerst
        -   Hören Sie auf Benachrichtigungen zweitens
            -   Bearbeiten +strom-modus-geändert,+textedit-geöffnet,+textedit-geändert,+textedit-geschlossen,+gerät-name-geändert
            -   Stellen Sie sicher, dass wir jede dieser Anfragen und ihr Format bearbeiten können...
        -   Gerätezustand dritten auffrischen
        -   Abfrage-textedit-Zustand viert auffrischen
            -   Textedit-Zustand aktualisieren
        -   Geräteicons fünft auffrischen
    -   Bei allen Änderungen nach der Wiederverbindung (über Benachrichtigung oder sonstiges)
        -   Gerät (gespeichert) und Gerätezustand (flüchtig) aktualisieren
    -   Nach Wiederverbindung/Trennung, aktualisieren Sie den Online-Status in der Fernansicht

## Verbesserung der Benutzerkommunikation rund um Gerätefähigkeiten

-   Aktualisieren Sie die Benutzerkommunikation, wenn Fehler auftreten können
    -   Wenn auf einen deaktivierten Button geklickt wird, öffnet sich ein Popover, um zu zeigen, warum er deaktiviert ist
        -   Zeigen Sie einen Info-Indikator auf dem Button an, um anzuzeigen, dass Informationen erhalten werden können, wenn darauf geklickt wird?
        -   Kopfhörer-Modus deaktiviert -> weil das Gerät diesen App keinen Kopfhörer-Modus unterstützt
        -   Lautstärkeregelung deaktiviert -> weil der Ton über HDMI ausgegeben wird, das keine Lautstärkeregler unterstützt?
    -   Wenn aktiv nach Geräten gescannt wird und keine neuen gefunden werden, zeigen Sie eine Warnmeldung unterhalb der Geräteliste an
        -   “Wir konnten Ihren Roku nicht wecken” (Herausfinden warum), (X)
        -   Mehr erfahren zeigt ein Popup mit einigen Gründen, warum dies passieren könnte
            -   Stellen Sie sicher, dass Ihr Gerät eingeschaltet ist und mit demselben Wifi-Netzwerk wie Ihre App verbunden ist. Wenn das immer noch nicht funktioniert, versuchen Sie, das Gerät manuell hinzuzufügen.
            -   Link https://roam.msd3.io/manually-add-tv.md und https://support.roku.com/article/115001480188 für weitere Fehlerbehebung oder Chat
-   Abzeichen für supportsWakeOnWLAN und supportsMute hinzufügen

## Unterstützung für ecp-Textedit

-   Aktualisieren Sie die Tastaturbehandlung, um ecp-Textedit bei `KeyboardEntry` zu unterstützen
    -   Zeigen Sie die Tastatur an, wenn Textedit geöffnet ist
    -   Verstecken Sie die Tastatur, wenn Textedit geschlossen ist
    -   Testen Sie, dass das Einfügen + Auswählen/Löschen im Textedit-Feld wie erwartet funktioniert
    -   Wenn ecp-Textedit unterstützt wird, ermöglichen Sie das Auswählen, Löschen von Text und das Verschieben des Cursors. Senden Sie einfach den Text jedes Mal erneut, wenn er sich ändert, wenn dies unterstützt wird.
    -   Wenn ecp-Textedit nicht unterstützt wird, gehen Sie zur aktuellen Verhaltensweise des Sendens von Tasten zurück
    -   Auf macOS zeigen Sie an, wenn Textedit aktiviert ist 
    -   Auf macOS erlauben Sie cmd+v und cmd+c und cmd+x zum Kopieren/Einfügen von/nach dem Puffer

Keyboard ECP Session Commands (Notizen)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Zu aktualisieren, wenn Unterstützung für iOS 17/macOS 15 (2025) eingestellt wird

-   Verwenden Sie Vorschau-Merkmale, um Beispieldaten in Vorschauen einzuführen
    -   Wie macht man das, wenn iOS 17 immer noch ein Faktor ist?
    -   Wie benutzt man @Previewable in Vorschauen, wenn iOS 17 immer noch ein Faktor ist??
-   SwiftData
    -   Verwenden Sie das neue #Index Makro für Models
    -   Verwenden Sie das neue #Unique Makro für Models
    -   Verwenden Sie Stapellöschung
-   TipKit
    -   Verwenden Sie CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
