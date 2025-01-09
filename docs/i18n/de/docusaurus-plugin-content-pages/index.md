---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Über Roam

Roam bietet alles, was Sie wollen, und nichts, was Sie nicht wollen

-   Läuft auf Mac, iPhone, iPad, Apple Watch, Vision Pro oder Apple TV!
-   Clevere Plattformintegration mit Tastaturkürzeln auf dem Mac, Verwendung der Hardware-Lautstärketasten zur Steuerung der Fernsehlautstärke auf iOS
-   Verwenden Sie Shortcuts und Widgets, um Ihren Fernseher zu steuern, ohne jemals die App zu öffnen!
-   Kopfhörermodus (a.k.a. privates Hören) Unterstützung auf Mac, iPad, iPhone, VisionOS und Apple TV (spielen Sie den Audio von Ihrem Fernseher über Ihr Gerät ab)
-   Entdecken Sie Geräte in Ihrem lokalen Netzwerk, sobald Sie die App öffnen
-   Intuitives Design mit dem Apple eigenen SwiftUI Designsystem
-   Schnell und leichtgewichtig, weniger als 8 MB auf allen Geräten und öffnet in weniger als einer halben Sekunde!
-   Open Source (https://github.com/msdrigg/roam)

## Häufige Probleme

-   Was kann ich tun, wenn Roam meinen Fernseher nicht automatisch erkennt?
    -   [Siehe hier](/manually-add-tv)
-   Warum funktioniert Kopfhörermodus (a.k.a. privates Hören) nicht auf meinem Fernseher?
    -   Der Kopfhörermodus funktioniert derzeit nicht auf einigen Fernsehern. Wenn der Kopfhörermodus mit Roam nicht funktioniert, aber mit der offiziellen Roku App funktioniert, teilen Sie bitte den Modellnamen Ihres Roku und alle anderen relevanten Informationen in einer E-Mail an [roam-support@msd3.io](mailto:roam-support@msd3.io). Ihr Bericht wird mir helfen herauszufinden, wo ich suchen muss, um diesen Fehler zu beheben.
-   Was ist, wenn ich ein anderes Problem habe oder nur Feedback geben möchte?
    -   Wenn es sich um einen Fehler handelt, wäre es am besten, einen Feedback-Bericht aus der Anwendung zu starten
        -   Gehen Sie in die Roam-App und öffnen Sie die Einstellungsseite
        -   Klicken Sie auf "Feedback senden". Dadurch wird ein Diagnosebericht erstellt, der mit dem Roam-Support (roam-support@msd3.io) geteilt werden kann
        -   Wenn Ihre App zum Absturz kommt, stellen Sie auch sicher, dass Ihre Analysen in den Einstellungen -> Datenschutz & Sicherheit -> Analytik & Verbesserungen aktiviert sind
            -   Aktivieren Sie "iPhone und Watch Analystics teilen" und dann "Mit App-Entwicklern teilen", damit Apple mir meldet, wenn Ihre App abstürzt
    -   Wenn es sich um eine Anforderung für eine neue Funktion handelt, können Sie eine E-Mail direkt (roam-support@msd3.io) senden oder direkt im Roam-App mit mir chatten (Einstellungen -> Chat mit dem Entwickler)
-   Warum funktionieren die Pfeiltasten manchmal nicht auf dem iPad?
    -   Dies wird verursacht, weil iPadOS manchmal die Kontrolle über die Pfeiltasten übernimmt und diese verwendet, um die Bildschirmtasten zu navigieren, bevor wir sie erkennen können
    -   Sie können dies umgehen, indem Sie in die Einstellungen -> Zugänglichkeit -> Tastaturen gehen und "Vollständiger Tastaturzugriff" deaktivieren oder alternativ zu den Einstellungen -> Zugänglichkeit -> Tastaturen -> Vollständiger Tastaturzugriff -> Befehle -> Basic gehen und die Befehle "Hoch bewegen", "Runter bewegen", "Links bewegen" und "Rechts bewegen" deaktivieren
-   Warum erscheint das Tippen auf meiner Tastatur nicht auf dem Fernseher
    -   Einige Roku Apps ignorieren die Eingabe der Hardwaretastatur. Sie können testen, ob dies ein Roam-Fehler oder ein Fehler in der App ist, indem Sie versuchen, die Tastatureingabefunktion in der offiziellen Roku-App zu verwenden und zu prüfen, ob dies funktioniert
    -   Apps mit bekannten Fehlern
        -   Prime Video
-   Warum funktioniert Roam auf meinem iPhone und der Mac-App, aber nicht auf meiner Apple Watch?
    -   Die WatchOS-App verbindet sich über die ECP-API des Fernsehers mit dem Fernseher, die auf einigen Roku-Fernsehern aktiviert werden muss. Um es zu aktivieren, gehen Sie zu **Einstellungen -> System -> Erweiterte Systemeinstellungen -> Steuerung durch mobile Apps** und stellen Sie sicher, dass der "Netzwerkzugriff" auf "Permissiv" eingestellt ist

## Weitere Ressourcen

Wenn Sie Fragen oder Probleme haben, kontaktieren Sie mich bitte unter: [roam-support@msd3.io](mailto:roam-support@msd3.io). Sie können auch direkt in der Roam-App mit mir chatten (Einstellungen -> Chat mit dem Entwickler).

-   [Datenschutzerklärung](/privacy)
-   [Kern-Repository auf GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Download im App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Änderungsprotokoll](/changes)
-   [Getestete Roku-Geräte](/tested-tvs)