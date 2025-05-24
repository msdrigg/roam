---
hide_table_of_contents: true
---

# Fernseher manuell hinzufügen

1. Finde die IP-Adresse deines Fernsehers
    - Schalte deinen Fernseher ein und navigiere zu **Einstellungen** > **Netzwerk** > **Informationen**
    - Die IP-Adresse sollte etwa wie 10.x.x.x, 172.x.x.x, 173.x.x.x oder 192.168.x.x aussehen
    - Auf dieser Seite wird möglicherweise eine „Gateway“-Adresse und eine „IP-Adresse“ angezeigt. Achte darauf, NICHT die „Gateway“-Adresse zu verwenden
2. Gehe in den Roam-Einstellungen auf „Gerät manuell hinzufügen“
3. Benenne dein Gerät nach Belieben und gib die IP-Adresse genau so ein, wie sie auf dem Roku TV angezeigt wird
4. Klicke auf Speichern. Jetzt sollte dein Roku sich verbinden und normal funktionieren

## Was tun, wenn du den Fernseher manuell hinzugefügt hast, Roam aber trotzdem keine Verbindung herstellen kann oder die Verbindung nicht richtig funktioniert?

Wenn Roam deinen Roku weiterhin nicht steuern kann, versuche bitte folgende Schritte:

-   [Nur WatchOS]: Gehe zu **Einstellungen -> System -> Erweiterte Systemeinstellungen -> Steuerung durch mobile Apps** und stelle sicher, dass dies auf **Erlauben** gesetzt ist
-   Stelle sicher, dass dein iOS-Gerät mit demselben WLAN-Netzwerk wie dein Roku TV verbunden ist
-   Stelle sicher, dass dein Fernseher eingeschaltet ist
-   Stelle sicher, dass die lokale Netzwerkberechtigung für Roam aktiviert ist (oder deaktiviere und aktiviere sie erneut, falls bereits aktiviert)
    -   Auf macOS: Gehe zu Systemeinstellungen -> Datenschutz & Sicherheit -> Lokales Netzwerk -> Roam
    -   Auf iOS: Gehe zu Einstellungen -> Apps -> Roam -> Lokales Netzwerk
-   Weitere Möglichkeiten findest du hier: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Was tun bei einer komplizierten Netzwerk/VPN-Konfiguration? Welche Protokolle verwendet diese App?

-   Roam nutzt verschiedene Protokolle zur Kommunikation mit dem Fernseher:
    -   TCP (HTTP/Websockets) auf Port 8060 zum Senden von Befehlen und Abfragen des Geräte-Status
    -   WOL Magic Packet (UDP-Multicast an Adresse 255.255.255.255), um den Fernseher aus dem Tiefschlaf zu wecken
    -   RDP (UDP) auf Port 6970 für den Ton im Kopfhörermodus
-   Alle Roku-Fernseher nutzen Port 8060, und dies kann auf dem Fernseher nicht geändert werden. Wenn du jedoch eine Portweiterleitung verwendest und einen anderen ausgehenden Port von Roam nutzen möchtest, ist das möglich. Gib dazu einfach `[IP]:[Port]` in das Feld „IP-Adresse“ ein, statt nur `[IP]`. Zum Beispiel trage `192.168.8.242:8061` ein, dann wird der Port `8061` verwendet.