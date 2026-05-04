---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Über Roam

Roam bietet alles, was du brauchst, und verzichtet auf alles Überflüssige

-   Läuft auf Mac, iPhone, iPad, Apple Watch, Vision Pro oder Apple TV!
-   Intelligente Plattformintegration mit Tastenkombinationen am Mac sowie Steuerung der TV-Lautstärke über die Hardware-Lautstärketasten unter iOS
-   Bediene dein TV-Gerät mit Kurzbefehlen und Widgets, ohne jemals die App öffnen zu müssen!
-   Kopfhörermodus (auch bekannt als Private Listening) wird auf Mac, iPad, iPhone, VisionOS und Apple TV unterstützt (übertrage den Ton deines Fernsehers auf dein Gerät)
-   Geräte im lokalen Netzwerk werden sofort bei App-Start erkannt
-   Intuitive Gestaltung mit Apples nativen SwiftUI-Designelementen
-   Schnell und ressourcenschonend – weniger als 8 MB auf allen Geräten und startet in weniger als einer halben Sekunde!
-   Open Source (https://github.com/msdrigg/roam)

## Funktionen

-   Fernbedienungen
    -   Roam beinhaltet die üblichen Roku-Fernbedienelemente, darunter Richtungs-, Auswahl-, Zurück-, Home-, Play/Pause- und entsprechende TV-Steuerungen, sofern diese vom Roku unterstützt werden.
    -   Die Lautstärkesteuerung funktioniert möglicherweise nicht mit Roku Sticks, da diese nur über HDMI verbunden werden und daher die TV-Lautstärke nicht über Roams Roku-Netzwerkbefehle steuern können.
-   Tastatureingabe
    -   Unter macOS gibt es keine separate Tastaturtaste. Ist das Roam-Fenster aktiv, funktioniert die Mac-Tastatur automatisch mit dem Fernseher.
    -   Unter iOS und iPadOS gibt es eine Tastaturtaste oben auf der Fernbedienung.
    -   watchOS bietet derzeit keine Tastaturfunktion.
    -   Einige Roku-Apps ignorieren Tastatureingaben von Fernbedienungs-Apps. Prime Video ist ein bekanntes Beispiel, bei dem die Tastatureingabe nicht funktioniert, da die Roku-App diese nicht akzeptiert.
-   Kopfhörermodus / Private Listening
    -   Private Listening überträgt den TV-Ton auf unterstützte Roku-Geräte durch dein eigenes Gerät.
    -   Private Listening wird in Roam auf Mac, iPad, iPhone, VisionOS und Apple TV unterstützt, funktioniert jedoch nicht mit jedem Roku TV.

## Häufige Probleme

-   Was kann ich tun, wenn Roam meinen Fernseher nicht automatisch findet?
    -   [Siehe hier](/manually-add-tv)
-   Roam funktioniert nicht richtig auf meiner Apple Watch
    -   Bitte gehe zu **Einstellungen -> System -> Erweiterte Systemeinstellungen -> Steuerung durch Mobile Apps** und stelle sicher, dass die Option auf **Zulässig** gesetzt ist.
-   Warum funktioniert der Kopfhörermodus (Private Listening) nicht auf meinem Fernseher?
    -   Der Kopfhörermodus funktioniert derzeit auf einigen Fernsehern nicht. Wenn der Kopfhörermodus in Roam nicht funktioniert, aber mit der offiziellen Roku-App, teile bitte den Modellnamen deines Roku und weitere relevante Details per E-Mail an [roam-support@msd3.io](mailto:roam-support@msd3.io) mit. Dein Bericht hilft mir, die Ursache zu finden, um diesen Fehler zu beheben.
-   Was kann ich tun, wenn ich ein anderes Problem habe oder Feedback geben möchte?
    -   Handelt es sich um einen Fehler, empfiehlt es sich, einen Fehlerbericht direkt aus der App zu senden:
        -   Öffne die Roam-App und gehe zur Einstellungsseite
        -   Tippe auf „Feedback senden“. Dadurch wird ein Diagnosebericht erstellt, der mit dem Support (roam-support@msd3.io) geteilt werden kann.
        -   Wenn deine App abstürzt, stelle sicher, dass die Analysedaten in Einstellungen -> Datenschutz & Sicherheit -> Analyse & Verbesserungen aktiviert sind
            -   Aktiviere „iPhone- & Watch-Analysen teilen“ und dann „Mit App-Entwicklern teilen“, damit bei Abstürzen deiner App ein Bericht an mich gesendet wird.
    -   Bei Funktionswünschen kannst du eine E-Mail senden (roam-support@msd3.io), mich direkt in der Roam-App kontaktieren (Einstellungen -> Chat mit dem Entwickler) oder dem [Roam Discord](https://discord.gg/FqaTNRccbG) beitreten.
-   Warum funktionieren die Pfeiltasten manchmal auf dem iPad nicht?
    -   Das liegt daran, dass iPadOS manchmal die Kontrolle über die Pfeiltasten übernimmt und sie für die Navigation der Bildschirmtasten verwendet, bevor Roam sie erkennt.
    -   Du kannst das umgehen, indem du zu Einstellungen -> Bedienungshilfen -> Tastaturen gehst und „Voller Tastaturzugriff“ deaktivierst oder alternativ unter Einstellungen -> Bedienungshilfen -> Tastaturen -> Voller Tastaturzugriff -> Tastenbefehle -> Grundfunktionen die Befehle „Nach oben“, „Nach unten“, „Nach links“ und „Nach rechts“ deaktivierst.
-   Warum erscheinen meine Tastatureingaben nicht auf dem Fernseher?
    -   Manche Roku-Apps ignorieren die Eingabe einer Hardwaretastatur. Ob es an Roam oder an der App liegt, kannst du testen, indem du die Tastatureingabe in der offiziellen Roku-App versuchst.
    -   Unter macOS gibt es keine eigene Tastaturtaste, weil die Mac-Tastatur automatisch funktioniert, wenn das Roam-Fenster aktiv ist. Unter iOS und iPadOS verwende die Tastaturtaste oben auf der Fernbedienung. watchOS unterstützt zurzeit keine Tastatureingabe.
    -   Apps mit bekannten Problemen:
        -   Prime Video
-   Warum funktioniert Roam auf meinem iPhone und Mac, aber nicht auf meiner Apple Watch?
    -   Die WatchOS-App verbindet sich mit dem Fernseher über dessen ECP-API. Diese muss bei manchen Roku-TVs aktiviert werden. Um sie zu aktivieren, gehe zu **Einstellungen -> System -> Erweiterte Systemeinstellungen -> Steuerung durch Mobile Apps** und stelle sicher, dass „Netzwerkzugriff“ auf „Zulässig“ gesetzt ist.

## Weitere Ressourcen

Wenn du Fragen oder Probleme hast, melde dich gerne unter: [roam-support@msd3.io](mailto:roam-support@msd3.io). Du kannst auch direkt in der Roam-App mit mir chatten (Einstellungen -> Chat mit dem Entwickler) oder dem [Roam Discord](https://discord.gg/FqaTNRccbG) beitreten.

-   [Datenschutzerklärung](/privacy)
-   [Core Repository auf GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Im App Store herunterladen](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Changelog](/changes)
-   [Getestete Roku-Geräte](/tested-tvs)