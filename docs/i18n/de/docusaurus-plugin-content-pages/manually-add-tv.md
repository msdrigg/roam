---
hide_table_of_contents: true
---

# Einen Fernseher manuell hinzufügen

1. Finden Sie die IP-Adresse Ihres Fernsehers
    - Schalten Sie Ihren Fernseher ein und navigieren Sie zu **Einstellungen** > **Netzwerk** > **Über**
    - Die IP-Adresse sollte wie 10.x.x.x, 172.x.x.x, 173.x.x.x oder 192.168.x.x aussehen
    - Auf dieser Seite könnte eine "Gateway"-Adresse und eine "IP-Adresse" aufgeführt sein. Stellen Sie sicher, dass Sie NICHT die "Gateway"-Adresse verwenden
2. Navigieren Sie zu den Roam-Einstellungen und klicken Sie auf "Gerät manuell hinzufügen"
3. Benennen Sie Ihr Gerät, wie Sie möchten, und geben Sie die Geräte-IP genau so ein, wie sie auf dem Roku TV angezeigt wird
4. Klicken Sie auf Speichern. Jetzt sollte Ihr Roku in der Lage sein, sich normal zu verbinden und zu funktionieren

## Was, wenn Sie den Fernseher manuell hinzufügen und Roam trotzdem keine Verbindung herstellen kann?

Wenn Roam Ihren Roku immer noch nicht steuern kann, versuchen Sie bitte die folgenden Schritte

-   Stellen Sie sicher, dass Ihr iOS-Gerät mit demselben WiFi-Netzwerk verbunden ist wie Ihr Roku TV
-   Stellen Sie sicher, dass Ihr Fernseher eingeschaltet ist
-   Stellen Sie sicher, dass die Lokale Netzwerkberechtigung für Roam aktiviert ist (oder deaktivieren und reaktivieren Sie sie, wenn sie bereits aktiviert ist)
    -   Auf macOS: Gehen Sie zu Systemeinstellungen -> Datenschutz und Sicherheit -> Lokales Netzwerk -> Roam
    -   Auf iOS: Gehen Sie zu Einstellungen -> Apps -> Roam -> Lokales Netzwerk
-   Weitere Möglichkeiten finden Sie hier [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Was ist, wenn ich ein kompliziertes Netzwerk-/VPN-Setup habe? Welche Protokolle verwendet diese App?

-   Roam verwendet zwei verschiedene Protokolle zur Kommunikation mit dem Fernseher
    -   TCP (HTTP/Websockets) auf Port 8060 zum Senden von Befehlen an den Fernseher
    -   WOL Magic Packet (UDP-Multicast an die Adresse 255.255.255.255), um den Fernseher aus einem tiefen Schlaf zu wecken
-   Alle Roku Fernseher nutzen den Port 8060 und es gibt keine Möglichkeit, dies auf der Fernseherseite zu ändern. Aber wenn Sie eine Art Portweiterleitung eingerichtet haben und einen anderen ausgehenden Port von Roam aus nutzen möchten, ist dies möglich. Sie müssen nur `<IP>:<Port>` in das Feld "IP-Adresse" eingeben, statt nur `<IP>`. Geben Sie z.B. `192.168.8.242:8061` ein und der ausgewählte Port wird verwendet.