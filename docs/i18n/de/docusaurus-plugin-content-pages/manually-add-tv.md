---
hide_table_of_contents: true
---

# TV manuell hinzufügen

1. Finde die IP-Adresse deines TVs
    - Schalte deinen TV ein und gehe zu **Einstellungen** > **Netzwerk** > **Informationen**
    - Falls du keine physische Fernbedienung oder eine andere Möglichkeit hast, den TV zu steuern, schaue stattdessen in der Admin-Oberfläche deines Routers oder in der Liste der DHCP-Clients nach der IP-Adresse des Roku
    - Die IP-Adresse sollte so aussehen: 10.x.x.x, 172.x.x.x, 173.x.x.x oder 192.168.x.x
    - Auf dieser Seite werden möglicherweise eine „Gateway“-Adresse und eine „IP-Adresse“ angezeigt. Stelle sicher, dass du NICHT die „Gateway“-Adresse verwendest
2. Navigiere zu den Roam-Einstellungen und klicke auf „Gerät manuell hinzufügen“
3. Vergib einen beliebigen Namen für dein Gerät und gib die IP-Adresse exakt so ein, wie sie auf deinem Roku TV angezeigt wird
4. Klicke auf Speichern. Jetzt sollte sich dein Roku verbinden und normal funktionieren

## Was tun, wenn du das TV-Gerät manuell hinzufügst und Roam es trotzdem nicht finden kann oder die Verbindung nicht richtig funktioniert?

Falls Roam deinen Roku immer noch nicht steuern kann, versuche bitte die folgenden Schritte:

-   [Nur WatchOS]: Gehe zu **Einstellungen -> System -> Erweiterte Systemeinstellungen -> Steuerung durch Mobile Apps** und stelle sicher, dass „Zulässig“ ausgewählt ist
-   Stelle sicher, dass dein iOS-Gerät mit demselben WLAN wie dein Roku TV verbunden ist
-   Stelle sicher, dass dein TV eingeschaltet ist
-   Stelle sicher, dass die Berechtigung „Lokales Netzwerk“ für Roam aktiviert ist (oder deaktiviere und aktiviere sie erneut, falls sie schon aktiviert ist)
    -   Auf macOS: Gehe zu Systemeinstellungen -> Datenschutz & Sicherheit -> Lokales Netzwerk -> Roam
    -   Auf iOS: Gehe zu Einstellungen -> Apps -> Roam -> Lokales Netzwerk
-   Falls sich deine Heimnetzwerkkonfiguration geändert hat und ein zuvor funktionierendes Gerät nicht mehr funktioniert, entferne das gespeicherte Gerät aus Roam und suche erneut danach
-   Falls dein Roku nicht mit dem WLAN verbunden ist und du keine physische Fernbedienung hast, folge den Verbindungsschritten der Roku Mobile App hier: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Weitere mögliche Lösungen findest du hier: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Was ist, wenn ich ein komplexes Netzwerk-/VPN-Setup habe? Welche Protokolle nutzt diese App?

-   Roam verwendet mehrere verschiedene Protokolle, um mit dem TV zu kommunizieren:
    -   TCP (HTTP/Websockets) auf Port 8060 für das Senden von Befehlen an den TV und zum Abfragen des Gerätestatus
    -   WOL-Magic Packet (UDP-Multicast an Adresse 255.255.255.255), um den TV aus dem Tiefschlaf aufzuwecken
    -   RDP (UDP) auf Port 6970 für den Audiostream im Kopfhörermodus
-   Alle Roku-TVs verwenden Port 8060 und dies kann auf der TV-Seite nicht geändert werden. Wenn du jedoch z. B. Port-Forwarding nutzt und einen anderen ausgehenden Port von Roam aus benutzen möchtest, ist das möglich. Gib einfach `[IP]:[Port]` in das Feld „IP-Adresse“ ein, anstatt nur `[IP]`. Beispiel: Gib `192.168.8.242:8061` ein, dann wird der Port `8061` verwendet.