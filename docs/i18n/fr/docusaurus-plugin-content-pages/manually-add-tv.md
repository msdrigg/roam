---
hide_table_of_contents: true
---

# Ajout manuel d'une TV

1. Trouvez l'adresse IP de votre TV
    - Allumez votre TV et allez dans **Paramètres** > **Réseau** > **À propos**
    - Si vous n'avez pas de télécommande physique ou un autre moyen de contrôler la TV, consultez l'interface d'administration de votre routeur domestique ou la liste des clients DHCP pour trouver l'adresse IP du Roku
    - L'adresse IP devrait ressembler à 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Cette page peut indiquer une adresse "Gateway" ainsi qu'une "Adresse IP". Assurez-vous de NE PAS utiliser l'adresse "Gateway"
2. Rendez-vous dans les paramètres de Roam et cliquez sur "Ajouter un appareil manuellement"
3. Nommez votre appareil comme vous le souhaitez, et saisissez exactement l'adresse IP affichée sur la TV Roku
4. Cliquez sur Enregistrer. Votre Roku devrait maintenant pouvoir se connecter et fonctionner normalement

## Que faire si vous ajoutez la TV manuellement et que Roam ne parvient toujours pas à se connecter ou que la connexion ne fonctionne pas correctement ?

Si Roam ne parvient toujours pas à contrôler votre Roku, essayez les étapes suivantes :

-   [WatchOS UNIQUEMENT] : Rendez-vous dans **Paramètres -> Système -> Paramètres Système Avancés -> Contrôle par applications mobiles** et assurez-vous que c'est réglé sur **Permissif**
-   Vérifiez que votre appareil iOS est connecté au même réseau WiFi que votre TV Roku
-   Vérifiez que votre TV est allumée
-   Assurez-vous que l'autorisation d'accès au réseau local est activée pour Roam (ou désactivez-la puis réactivez-la si elle l'est déjà)
    -   Sur macOS : Allez dans Réglages Système -> Confidentialité et Sécurité -> Réseau Local -> Roam
    -   Sur iOS : Allez dans Réglages -> Apps -> Roam -> Réseau Local
-   Si la configuration de votre réseau domestique a changé et qu'un appareil qui fonctionnait auparavant ne fonctionne plus, supprimez l'appareil enregistré dans Roam et recherchez-le à nouveau
-   Si le Roku n'est pas connecté au WiFi et que vous n'avez pas de télécommande physique, suivez les instructions de connexion de l'application mobile Roku ici : [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Consultez d'autres possibilités ici [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Et si j'ai une configuration réseau/VPN complexe ? Quels protocoles cette application utilise-t-elle ?

-   Roam utilise plusieurs protocoles différents pour communiquer avec la TV
    -   TCP (HTTP/Websockets) sur le port 8060 pour l'envoi de commandes à la TV et la récupération de l'état de l'appareil
    -   Paquet magique WOL (UDP multicast à l'adresse 255.255.255.255) pour réveiller la TV d'une veille profonde
    -   RDP (UDP) sur le port 6970 pour le mode audio casque
-   Tous les téléviseurs Roku utilisent le port 8060 et il n'est pas possible de le modifier côté TV. Toutefois, si vous avez un système de redirection de ports et souhaitez utiliser un port sortant différent depuis Roam, c'est possible. Il vous suffit de saisir `[IP]:[Port]` dans le champ "Adresse IP" au lieu de simplement `[IP]`. Par exemple, entrez `192.168.8.242:8061` et le port `8061` sera utilisé.