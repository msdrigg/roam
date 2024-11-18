---
hide_table_of_contents: true
---

# Roam Roadmap

## Abgeschlossene Arbeit für das nächste Update

- Kontroll-Widgets hinzugefügt: Spielen, Stummschalten, Lautstärke ändern und Auswahl vom Kontrollzentrum!
- Verbesserte Textfeldverwaltung für viele Roku-Apps 
    - Automatisches Öffnen des Textfelds, wenn die Textbearbeitung verfügbar ist
    - Kopieren, Ausschneiden, Einfügen von macOS
    - Kopieren, Ausschneiden, Einfügen + allgemeine Bearbeitung auf iOS
- Besserer Bericht über lokale Netzwerkberechtigungen und Konnektivität
- Verbesserungen der Verbindungsstabilität

## Kommt demnächst

-   Aktuelle laufende Arbeiten
    -   Stellen Sie sicher, dass die Texteingabe auf iOS nicht unter die Tastatur rutscht (wie es gerade der Fall ist)
    -   Beheben Sie macOS-Widgets
    -   Veröffentlichen Sie die iOS-Version im App Store
        - Warten auf die Nachverfolgung des Einspruchs
    -   Führen Sie bessere Tests auf iOS und macOS durch, um zu prüfen, ob das System sich wieder verbindet und in den folgenden Szenarien verbunden bleibt
        - Nach langer Wartezeit
        - Beim erneuten Betreten aus dem Hintergrund
        - Beim Einschalten des Fernsehers aus dem AUS-Zustand
        - Bei Wiederverbindung mit dem Internet
        - Beim Wechseln der Geräte

-   Als nächstes: Hinzufügen eines +30 Sekunden Stummschalttimers mit Countdown
    -   Halten Sie die Stummschaltung gedruckt, um sie für +30 Sekunden stummzuschalten
    -   Klicken Sie erneut, um die Stummschaltung aufzuheben und sie zu stornieren
    -   Zeigen Sie einen Indikator unter der Stummschalttaste
        -   Der Fortschrittsbalken hat einen linearen Fortschrittsanzeiger
        -   Der Fortschrittsbalken hat zwei Tasten: +30 Sekunden, Abbrechen
        -   Zeigen Sie sie unter dem Haupttastenfeld an, damit sie nahe bei der Stummschaltung ist
    -   Machen Sie die +30 konfigurierbar für 30, 15, 60 Sekunden Stummschaltoptionen

-   Zukunft: Bereitstellung einer optionalen minimalistischen Ansicht auf iOS, die der Siri-Fernbedienungsansicht genau entspricht
    -   https://support.apple.com/de-de/guide/tv/nutzung-des-ios-oder-ipadOS-kontrollzentrums-atvb701cadc1/tvos
    -   Unterstützung für VisionOS-Gesten ebenfalls...

## Allgemeine zukünftige Ideen

-   Schreiben Sie einen Blogbeitrag über den Discord-Bot und verweisen Sie auf meine MessageView
    - Machen Sie die MessageView eigenständiger
-   Schreiben Sie einen Blogbeitrag über die automatische Übersetzung und die Logik dahinter
-   Schreiben Sie einen Blogbeitrag über NWConnection vs URLSession für Websockets
-   Schreiben Sie einen Blogbeitrag über benutzerdefinierte Tastaturkürzel
-   Schreiben Sie einen Blogbeitrag über ECP Textedit API
-   Schreiben Sie einen Blogbeitrag über Kontrollzentrum-Widgets

-   Benutzerdefiniertes Menüleistensymbol erstellen

-   Wie macht man eine Sprache-zu-Text- oder allgemeine Sprachbefehle?
    - Müssen das Roku Voice Remote UDP-Protokoll reverse-engineern
    - Oder müssen eine benutzerdefinierte Text-zu-Sprache-Funktion mit der Remote-Tasten-Engine hinzufügen?

-   Automatische Screenshot-Erfassung

    -   Verwenden Sie UITests, um tatsächliche Screenshots für alle Gerätegrößen und lokale Einstellungen zu erhalten
    -   Nutzen Sie AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w, um die Screenshots in die Frames zu bekommen
    -   Oder etwas anderes
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Testen Sie weitere Tastaturtricks für das iPad
    -   Verwenden Sie für eines GCKeyboard
    -   Verwenden Sie für ein zweites FocusEnvironment
    -   Stellen Sie sicher, dass die Lösung, die für iOS verwendet wird, die Texteingabe in Nachrichten/Tastatureingaben nicht unterbricht

-   UI-Tests
    -   Testen Sie, ob das Gerät hinzugefügt, dass es im Geräteauswahlfeld wird und von Roam ausgewählt wird
    -   Testen Sie, ob der Benutzer zu Einstellungen -> Geräte navigieren kann
    -   Testen Sie, ob der Benutzer zu Einstellungen -> Nachrichten navigieren kann
    -   Testen Sie, ob der Benutzer zu Einstellungen -> Über navigieren kann
    -   Testen Sie, ob der Benutzer Geräte bearbeiten/löschen kann
    -   Testen Sie, ob der Benutzer auf Tasten klicken kann, sobald Geräte hinzugefügt wurden
    -   Testen Sie, ob der Benutzer ein Banner für keine Geräte sieht, wenn es auftaucht
    -   Testen Sie, ob der Benutzer Applinks sieht
    -   Beziehen Sie sich auf die SwiftData TestingModelContainer für ModelContainer
    -   Hier finden Sie Informationen darüber, wie Sie Tests einrichten: https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad

## Bug Fixes

-   Herausfinden, ob die Schleife von Aufrufen an `nextPacket` sinnvoll ist.
    -   Statt alle 10 ms zu schleifen und zu hoffen, dass die Zeitstempelung korrekt ist, sollte ich stattdessen versuchen, empfangene Pakete zu schleifen und sie zur Host-Zeit `10ms * globalSequenceNumber + startHostTime` und SampleTime zu `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime` zu planen
    -   Dann kann ich von einer `for await` Schleife über die Uhr zu einer `while !Task.isCancelled` Schleife mit einer `Task.sleep` darin wechseln.
    -   Okay, also müssen wir alle 10 ms eine Schleife durchlaufen und versuchen, das letzte Paket abzuziehen und dann zur gegebenen Zeit zu planen
    -   Immer, wenn wir einen Audiosync durchführen
        -   Wir haben lastRenderTime + ein Sync-Paket
        -   Schätzen Sie die Paketnummer, die wir zum gegebenen Zeitpunkt aussenden sollten + die Synchronisationszeit
            -   Render Time + additional

## Verbessern der Benachrichtigungen der Benutzer über Informationen/Status/Fähigkeitsmanagement

-   Wenn das Gerät mit WOL eingeschaltet und nach 5 Sekunden nicht verbunden ist oder beim Einschalten des Geräts sofort ausfällt, zeigen Sie eine Warnmeldung unter der WLAN-Meldung an
    -   “Wir konnten Ihren Roku nicht wecken” (Mehr erfahren) (Nicht wieder für dieses Gerät anzeigen), (X)
    -   Mehr erfahren zeigt einige Gründe warum
        -   Sie sind nicht mit demselben Netzwerk verbunden (Zeigen Sie den letzten Gerätenetzwerknamen an. Fragen Sie, ob der Benutzer mit diesem Netzwerk verbunden ist)
        -   Ihr Gerät ist im Tiefschlaf (wurde nicht kürzlich heruntergefahren) und kann nicht geweckt werden
            -   Ihr Gerät unterstützt WWOL nicht und ist mit dem WLAN verbunden
            -   Ihr Gerät unterstützt WWOL oder WOL nicht
        -   Ihr Netzwerk ist nicht so eingerichtet, dass wir Wakeup-Befehle an das Gerät senden können
-   Wenn Sie auf eine deaktivierte Schaltfläche klicken, wird eine Benachrichtigung angezeigt, die zeigt, warum sie deaktiviert ist
    -   Zeigen Sie einen Info-Indikator auf der Schaltfläche an, um anzuzeigen, dass Informationen empfangen werden können, wenn darauf geklickt wird?
    -   Kopfhörermodus deaktiviert -> weil das Gerät den Kopfhörermodus für diese App nicht unterstützt
    -   Lautstärkeregelung deaktiviert -> weil der Ton über HDMI ausgegeben wird, das keine Lautstärkeregelung unterstützt?
-   Wenn aktiv nach Geräten gescannt und keine neuen gefunden werden, zeigen Sie eine Warnmeldung unter der Geräteliste an
    -   “Wir konnten Ihren Roku nicht wecken” (Herausfinden warum), (X)
    -   Find out more eine Popup mit einigen Gründen, warum dies passieren könnte
        -   Stellen Sie sicher, dass Ihr Gerät eingeschaltet ist und mit demselben WLAN-Netzwerk wie Ihre App verbunden ist. Wenn das immer noch nicht funktioniert, versuchen Sie, das Gerät manuell hinzuzufügen.
        -   Verlinken Sie https://roam.msd3.io/manual-add-tv.de.md und https://support.roku.com/artikel/115001480188 für weitere Fehlerbehebung oder Chat
-   Abzeichen hinzufügen für supportsWakeOnWLAN und supportsMute

## Zu aktualisieren, wenn die Unterstützung für iOS 17/macOS 14 (Feb 2026) beendet wird

-   Entfernen Sie die @available(iOS 18)-Tags
-   Verwenden Sie Vorschaueigenschaften, um Beispieldaten in Vorschauen einzufügen
-   SwiftData
    -   Verwenden Sie das neue #Index-Makro für Modelle
    -   Verwenden Sie das neue #Unique-Makro für Modelle
    -   Verwenden Sie die Stapellöschung
-   TipKit
    -   Verwenden Sie CloudkitContainer https://developer.apple.com/videos/wwdc2024/10070/?time=698