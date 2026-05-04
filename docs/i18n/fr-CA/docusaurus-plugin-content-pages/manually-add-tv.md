---
hide_table_of_contents: true
---

# Ajouter manuellement une télé

1. Trouvez l’adresse IP de votre télé
    - Allumez votre télé et allez dans **Paramètres** > **Réseau** > **À propos**
    - Si vous n’avez pas de télécommande physique ou un autre moyen de contrôler la télé, consultez l’interface d’administration de votre routeur domestique ou la liste des clients DHCP afin de trouver l’adresse IP du Roku
    - L’adresse IP devrait ressembler à 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Cette page pourrait afficher une adresse « Gateway » et une « Adresse IP ». Assurez-vous de NE PAS utiliser l’adresse « Gateway »
2. Allez dans les paramètres de Roam et cliquez sur « Ajouter un appareil manuellement »
3. Nommez votre appareil comme vous le souhaitez et entrez l’adresse IP exactement comme indiquée sur la télé Roku
4. Cliquez sur Enregistrer. Votre Roku devrait maintenant pouvoir se connecter et fonctionner normalement

## Que faire si vous ajoutez la télé manuellement, mais que Roam ne peut toujours pas se connecter ou que la connexion ne fonctionne pas correctement?

Si Roam ne peut toujours pas contrôler votre Roku, essayez les étapes suivantes

-   [WatchOS SEULEMENT] : Veuillez aller dans **Paramètres -> Système -> Paramètres système avancés -> Contrôle par applications mobiles** et assurez-vous que c’est réglé sur **Permissif**
-   Assurez-vous que votre appareil iOS est connecté au même réseau WiFi que votre télé Roku
-   Assurez-vous que votre télé est allumée
-   Assurez-vous que l’autorisation Réseau local est activée pour Roam (ou désactivez et réactivez-la si elle l’est déjà)
    -   Sur macOS : Allez dans Réglages du système -> Confidentialité et sécurité -> Réseau local -> Roam
    -   Sur iOS : Allez dans Réglages -> Apps -> Roam -> Réseau local
-   Si la configuration de votre réseau domestique a changé et qu’un appareil qui fonctionnait auparavant ne fonctionne plus, supprimez l’appareil sauvegardé de Roam et recherchez-le à nouveau
-   Si le Roku n’est pas connecté au WiFi et que vous n’avez pas de télécommande physique, suivez les étapes de connexion de l’application mobile Roku ici : [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Voyez d’autres possibilités ici [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Si j’ai une configuration réseau/VPN compliquée, quels protocoles cette application utilise-t-elle?

-   Roam utilise plusieurs protocoles pour communiquer avec la télé
    -   TCP (HTTP/Websockets) sur le port 8060 pour envoyer des commandes à la télé et interroger l’état de l’appareil
    -   Paquet magique WOL (multidiffusion UDP à l’adresse 255.255.255.255) pour réveiller la télé d’un sommeil profond
    -   RDP (UDP) sur le port 6970 pour le flux audio en mode écouteurs
-   Toutes les télés Roku utilisent le port 8060 et il n’est pas possible de changer cela côté télé. Mais si vous avez une configuration de redirection de ports et souhaitez utiliser un port sortant différent depuis Roam, c’est possible. Il suffit d’entrer `[IP]:[Port]` dans le champ « Adresse IP » au lieu de juste `[IP]`. Par exemple, entrez `192.168.8.242:8061` et le port `8061` sera utilisé.