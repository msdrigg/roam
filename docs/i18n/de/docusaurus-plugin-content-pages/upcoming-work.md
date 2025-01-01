---
hide_table_of_contents: true
---

# Roam Roadmap

## Abgeschlossene Arbeiten für das nächste Update

-   Kontroll-Widgets hinzugefügt: Spielen, Stummschalten, Lautstärke ändern und Auswählen aus dem Kontrollzentrum!
-   Verbesserte Textfeld-Behandlung für viele Roku-Apps
    -   Textfeld automatisch öffnen, wenn Textbearbeitung verfügbar ist
    -   Kopieren, Ausschneiden, Einfügen von macOS (mit Tastatur)
    -   Kopieren, Ausschneiden, Einfügen + Allgemeines Bearbeiten auf iOS
-   Bessere Berichterstattung über lokale Netzwerkberechtigungen und Konnektivität
-   Verbesserte Tastaturfunktionalität
-   Verbesserungen der Verbindungsstabilität

## Kommt Bald

-   Hinzufügen von Langdruck-Optionen zu den Tasten
    -   Langdrücken der rechten Pfeiltaste zum schnellen Vorlauf
    -   Langdrücken der linken Pfeiltaste zum schnellen Rücklauf
    -   Langdrücken zum langen Stummschalten
        -   Konfigurierbaren +30 zu 30, 15, 60 Sekunden Stummschalten-Optionen machen
        -   Banner mit +30 Sek., x zum Abbrechen, Hintergrund Fortschritt anzeigen
            -   Zeigen Sie es unter dem Haupt-Tastenfeld an, damit es nahe an der Stummschaltung ist
        -   Abgebrochen, wenn erneut stummgeschaltet wird (und führt auch einen API-Aufruf durch)
-   Fehler bei macOS-Widgets beheben

-   Zukunft: Bereitstellen einer optionalen minimalistischen Ansicht auf iOS, die die Siri Remote-Ansicht genau nachbildet
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Auch VisionOS Gesten unterstützen...

## Allgemeine Zukünftige Ideen

-   Benutzerdefiniertes Menü Symbol erstellen

-   Wie macht man Sprach-zu-Text oder allgemeine Sprachbefehle?

    -   Man müsste das Roku-Sprach-Fernbedienungs-UDP-Protokoll reverse-engineeren
    -   Oder man müsste benutzerdefinierte Text-zu-Sprachausgabe mit Fernsteuerungs-Engine hinzufügen?

-   Automatisierung der Bildschirmaufnahme

    -   Verwendung von UITests um tatsächliche Bildschirmphotos für alle Gerätgrößen und Ortszeiten zu erhalten
    -   Verwendung von AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w um die Bildschirmphotos in den Rahmen zu bekommen
    -   Oder etwas anderes
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Probieren Sie weitere Tastaturhacks auf dem iPad aus

    -   GCKeyboard ausprobieren
    -   FocusEnvironment probieren
    -   Sicherstellen, dass die für iOS verwendete Lösung die Texteingabe in Nachrichten/Tastatureingabe nicht unterbricht

-   UI Tests
    -   Test, ob das Gerät bei Hinzufügung in der Geräteauswahl angezeigt und von der Roam ausgewählt wird
    -   Test, ob der Benutzer zu Einstellungen -> Geräte navigieren kann
    -   Test, ob der Benutzer zu Einstellungen -> Nachrichten navigieren kann
    -   Test, ob der Benutzer zu Einstellungen -> Über navigieren kann
    -   Test, ob der Benutzer Geräte bearbeiten/löschen kann
    -   Test, dass der Benutzer die Tasten drücken kann, sobald Geräte hinzugefügt wurden
    -   Test, dass der Benutzer ein Banner für keine Geräte sieht, wenn es erscheint
    -   Test, dass der Benutzer AppLinks sieht
    -   Bezüglich Swiftdat auf testingmodelcontainer zur Modellcontainer Bezug nehmen
    -   Hier https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad Bezug nehmen, um zu erfahren, wie Tests eingerichtet werden können

## Fehlerbehebungen

-   Herausfinden, ob die Schleife der Aufrufe zur `nextPacket` Sinn ergibt.
    -   Anstatt alle 10 ms zu schleifen und darauf zu hoffen, dass die Zeitstempel korrekt sind, sollte ich vielleicht versuchen, die empfangenen Pakete zu durchlaufen und sie zur Host-Zeit `10ms * globalSequenceNumber + startHostTime` und sampleTime zu `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime` zu planen
    -   Dann kann ich von einer `for await` Schleife über die Uhr zu einer `while !Task.isCancelled` Schleife mit einem `Task.sleep` darin wechseln.
    -   Okay, also wir müssen alle 10 ms schleifen und versuchen, das letzte Paket abzurufen und dann zu dieser Zeit zu planen
    -   Jedes Mal, wenn wir eine Audio-Synchronisation durchführen
        -   Wir haben lastRenderTime + ein Sync-Paket
        -   Schätzen Sie die Paketnummer, die wir herausgeben sollten, + die Synchronisationszeit
            -   Render-Zeit + zusätzlich

## Verbesserung der Benutzerkommunikation über Info/Status/Fähigkeiten Management

-   Bei Einschalten des Geräts mit WOL und Nichtverbindung nach 5 Sekunden, oder bei sofortigem Fail nach dem Einschalten, eine Warnmeldung unter der Wi-Fi Anzeige anzeigen
    -   „Wir konnten Ihr Roku nicht aufwecken“ (Mehr erfahren) (Nicht mehr für dieses Gerät anzeigen), (X)
    -   „Mehr erfahren“ zeigt einige Gründe warum
        -   Sie sind nicht mit demselben Netzwerk verbunden (Zeigen Sie den letzten Gerätenetzwerknamen. Fragen Sie, ob der Benutzer mit diesem Netzwerk verbunden ist)
        -   Ihr Gerät ist im Tiefschlaf (wurde kürzlich nicht heruntergefahren) und kann nicht aufgeweckt werden
            -   Ihr Gerät unterstützt WWOL nicht und ist mit WiFi verbunden
            -   Ihr Gerät unterstützt weder WWOL noch WOL
        -   Ihr Netzwerk ist nicht so eingerichtet, dass wir Aufweckbefehle an das Gerät senden können.
-   Bei Klick auf eine deaktivierte Schaltfläche, Benachrichtigung zeigen, die erklärt, warum sie deaktiviert ist
    -   Sollte man einen Info-Indikator auf der Schaltfläche anzeigen, um zu zeigen, dass Informationen erhalten werden können, wenn darauf geklickt wird?
    -   Kopfhörermodus deaktiviert -> weil das Gerät diesen App keinen Kopfhörermodus unterstützt
    -   Lautstärkeregelung deaktiviert -> weil der Ton über HDMI ausgegeben wird, was keine Lautstärkeregelung unterstützt?
-   Wenn aktiv nach Geräten gesucht wird und keine neuen gefunden werden, zeigen Sie eine Warnmeldung unterhalb der Geräteliste an
    -   „Wir konnten Ihr Roku nicht aufwecken“ (Herausfinden, warum), (X)
    -   „Herausfinden, warum“ zeigt ein Popup mit einigen Gründen, warum dies passieren könnte
        -   Stellen Sie sicher, dass Ihr Gerät eingeschaltet ist und mit demselben Wi-Fi-Netzwerk wie Ihre App verbunden ist. Wenn das immer noch nicht funktioniert, versuchen Sie, das Gerät manuell hinzuzufügen.
        -   Verlinken zu https://roam.msd3.io/manually-add-tv.md und https://support.roku.com/article/115001480188 für weitere Problembehebung oder Chat
-   Abzeichen für supportsWakeOnWLAN und supportsAudioControls hinzufügen

## Bei Beendigung der Unterstützung für iOS 17/macOS 14 zu aktualisieren (Feb 2026)

-   Entfernen Sie @available(ios 18) Markierungen
-   Verwendung von Preview-Traits zur Injizierung von Stichprobendaten in Vorschauen
-   SwiftData
    -   Verwendung des neuen #Index Makros für Modelle
    -   Verwendung des neuen #Unique Makros für Modelle
    -   Batch-Löschung verwenden
-   TipKit
    -   Verwendung von CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698