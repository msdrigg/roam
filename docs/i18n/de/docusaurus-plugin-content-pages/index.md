---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Über Roam

Roam bietet alles, was Sie wollen, und nichts, was Sie nicht wollen

-   Läuft auf Mac, iPhone, iPad, Apple Watch, Vision Pro oder Apple TV!
-   Smarte Plattformintegration mit Tastenkombinationen auf dem Mac, Nutzung der Hardware-Lautstärketasten zur Steuerung der TV-Lautstärke auf iOS
-   Nutzen Sie Shortcuts und Widgets zur Steuerung Ihres Fernsehers, ohne die App jemals zu öffnen!
-   Unterstützung des Kopfhörermodus (auch als private Hörmodus bekannt) auf Mac, iPad, iPhone, VisionOS und Apple TV (spielen Sie den Ton von Ihrem Fernseher über Ihr Gerät ab)
-   Entdecken Sie Geräte in Ihrem lokalen Netzwerk, sobald Sie die App öffnen
-   Intuitives Design mit dem nativen SwiftUI-Designsystem von Apple
-   Schnell und leicht, weniger als 8 MB auf allen Geräten und in weniger als einer halben Sekunde geöffnet!
-   Open Source (https://github.com/msdrigg/roam)

## Häufige Probleme

-   Was kann ich tun, wenn Roam meinen Fernseher nicht automatisch erkennt?
    -   [Hier sehen](/manually-add-tv)
-   Warum funktioniert der Kopfhörer Modus (auch als privates Hören bekannt) nicht auf meinem Fernseher?
    -   Der Kopfhörermodus funktioniert derzeit auf einigen Fernsehern nicht. Wenn der Kopfhörermodus mit Roam nicht funktioniert, aber mit der offiziellen Roku-App funktioniert, teilen Sie bitte den Modellnamen Ihres Roku und alle anderen relevanten Informationen in einer E-Mail an [roam-support@msd3.io](mailto:roam-support@msd3.io). Ihr Bericht wird mir helfen herauszufinden, wo ich suchen muss, um diesen Fehler zu beheben.
-   Was ist, wenn ich ein anderes Problem habe oder nur Feedback geben möchte?
    -   Wenn es sich um einen Bug handelt, wäre es am besten, einen Feedback-Bericht aus der Anwendung zu starten
        -   Gehen Sie in die Roam-App und öffnen Sie die Einstellungsseite
        -   Klicken Sie auf "Feedback senden". Dies generiert einen Diagnosebericht, der mit dem Roam-Support (roam-support@msd3.io) geteilt werden kann
        -   Wenn Ihre App abstürzt, stellen Sie außerdem sicher, dass Ihre Analysen in Einstellungen -> Datenschutz & Sicherheit -> Analyse & Verbesserungen aktiviert sind
            -   Schalten Sie "iPhone & Watch Analytics teilen" ein und dann "Mit App-Entwicklern teilen", damit Apple mir meldet, wenn Ihre App abstürzt
    -   Wenn es eine Anforderung für eine neue Funktion ist, können Sie eine E-Mail senden (roam-support@msd3.io), mit mir direkt in der Roam-App chatten (Einstellungen -> Chat mit dem Entwickler) oder dem [Roam Discord](https://discord.gg/FqaTNRccbG) beitreten.
-   Warum funktionieren die Pfeiltasten manchmal nicht auf dem iPad?
    -   Dies liegt daran, dass iPadOS manchmal die Kontrolle über die Pfeiltasten übernimmt und sie zur Navigation der Bildschirmtasten nutzt, bevor wir sie erkennen können
    -   Sie können dieses Problem umgehen, indem Sie in den Einstellungen -> Zugänglichkeit -> Tastaturen gehen und die "Volltastaturzugriff" deaktivieren oder alternativ zu Einstellungen -> Zugänglichkeit -> Tastaturen -> Volltastaturzugriff -> Befehle -> Grundlagen gehen und die Befehle "Hoch verschieben", "Runter verschieben", "Links verschieben" und "Rechts verschieben" deaktivieren
-   Warum erscheint das Tippen auf meiner Tastatur nicht auf dem Fernseher
    -   Bei einigen Roku-Apps ignoriert die App die Tastatureingabe der Hardware. Sie können testen, ob dies ein Roam-Bug oder ein Fehler in der App ist, indem Sie versuchen, die Tastatureingabefunktion in der offiziellen Roku-App zu verwenden und zu prüfen, ob dies funktioniert
    -   Apps mit bekannten Fehlern
        -   Prime Video
-   Warum funktioniert Roam auf meinem iPhone und der Mac-App, aber nicht auf meiner Apple Watch?
    -   Die WatchOS-App verbindet sich über die ECP-API des Fernsehers mit dem Fernseher, die auf einigen Roku-Fernsehern aktiviert sein muss. Um sie zu aktivieren, gehen Sie zu **Einstellungen -> System -> Erweiterte Systemeinstellungen -> Steuerung durch mobile Apps** und stellen Sie sicher, dass "Netzwerkzugriff" auf "Permissiv" eingestellt ist

## Weitere Ressourcen

Wenn Sie Fragen oder Probleme haben, kontaktieren Sie mich bitte unter: [roam-support@msd3.io](mailto:roam-support@msd3.io). Sie können auch direkt in der Roam-App mit mir chatten (Einstellungen -> Chat mit dem Entwickler) oder dem [Roam Discord](https://discord.gg/FqaTNRccbG) beitreten.

-   [Datenschutzerklärung](/privacy)
-   [Core Repository auf GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Im App Store herunterladen](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Änderungsprotokoll](/changes)
-   [Getestete Roku-Geräte](/tested-tvs)