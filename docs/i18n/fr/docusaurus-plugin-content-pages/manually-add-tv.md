---
hide_table_of_contents: true
---

# Ajouter une TV manuellement

1. Trouver l'adresse IP de votre TV
    - Allumez votre TV et allez dans **Paramètres** > **Réseau** > **À propos**
    - L'adresse IP doit ressembler à 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Cette page peut indiquer une adresse "Passerelle" et une "Adresse IP". Assurez-vous de NE PAS utiliser l'adresse "Passerelle"
2. Allez dans les paramètres de Roam et cliquez sur "Ajouter un appareil manuellement"
3. Nommez votre appareil comme vous le souhaitez et saisissez l'adresse IP exactement comme affichée sur le Roku TV
4. Cliquez sur Sauvegarder. Votre Roku devrait maintenant pouvoir se connecter et fonctionner normalement

## Que faire si, après avoir ajouté la TV manuellement, Roam n'arrive toujours pas à se connecter ou la connexion ne fonctionne pas correctement ?

Si Roam ne parvient toujours pas à contrôler votre Roku, veuillez essayer les étapes suivantes

-   [WatchOS UNIQUEMENT] : Rendez-vous dans **Paramètres -> Système -> Paramètres système avancés -> Contrôle via les applications mobiles** et assurez-vous que l'option est réglée sur **Permissif**
-   Assurez-vous que votre appareil iOS est connecté au même réseau WiFi que votre Roku TV
-   Assurez-vous que votre TV est allumée
-   Assurez-vous que l'autorisation "Réseau local" est activée pour Roam (ou désactivez-la puis réactivez-la si elle l'est déjà)
    -   Sur macOS : Allez dans Réglages système -> Confidentialité et sécurité -> Réseau local -> Roam
    -   Sur iOS : Allez dans Réglages -> Applications -> Roam -> Réseau local
-   Consultez d'autres possibilités ici [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Et si j'ai un réseau ou une configuration VPN compliquée ? Quels protocoles utilise cette application ?

-   Roam utilise différents protocoles pour communiquer avec la TV
    -   TCP (HTTP/Websockets) sur le port 8060 pour envoyer des commandes à la TV et interroger l'état du périphérique
    -   Paquet magique WOL (UDP multicast à l’adresse 255.255.255.255) pour sortir la TV de la veille profonde
    -   RDP (UDP) sur le port 6970 pour la diffusion audio du mode écouteurs
-   Tous les Roku TV utilisent le port 8060 et il n'est pas possible de le modifier côté TV. Mais si vous avez une configuration de redirection de port et souhaitez utiliser un port sortant différent depuis Roam, c'est possible. Vous devez simplement entrer `[IP]:[Port]` dans le champ "Adresse IP" au lieu de seulement `[IP]`. Par exemple, saisir `192.168.8.242:8061` utilisera le port `8061`.