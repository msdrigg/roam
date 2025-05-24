---
hide_table_of_contents: true
---

# Ajouter manuellement une télé

1. Trouvez l’adresse IP de votre télé  
    - Allumez votre télé et allez dans **Paramètres** > **Réseau** > **À propos**
    - L’adresse IP devrait ressembler à 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Cette page affichera peut-être une adresse de « passerelle » et une « adresse IP ». Assurez-vous de NE PAS utiliser l’adresse de « passerelle »
2. Rendez-vous dans les paramètres de Roam et cliquez sur « Ajouter un appareil manuellement »
3. Nommez votre appareil comme bon vous semble et entrez l’adresse IP exactement comme elle s’affiche sur la télé Roku
4. Cliquez sur Enregistrer. Votre Roku devrait maintenant être capable de se connecter et fonctionner normalement

## Que faire si vous ajoutez la télé manuellement et que Roam n’arrive toujours pas à se connecter ou que la connexion ne fonctionne pas correctement ?

Si Roam ne parvient toujours pas à contrôler votre Roku, essayez ces étapes :

-   [WatchOS SEULEMENT] : Allez dans **Paramètres -> Système -> Paramètres système avancés -> Contrôle via des applications mobiles** et assurez-vous que l’option soit mise à **Permissif**
-   Vérifiez que votre appareil iOS est connecté au même réseau WiFi que votre télé Roku
-   Assurez-vous que votre télé est allumée
-   Assurez-vous que la permission « Réseau local » soit bien activée pour Roam (sinon, désactivez-la puis réactivez-la)
    -   Sur macOS : Allez dans Réglages du système -> Confidentialité et sécurité -> Réseau local -> Roam
    -   Sur iOS : Allez dans Réglages -> Apps -> Roam -> Réseau local
-   Voyez d’autres pistes ici : [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Si j’ai un réseau ou une configuration VPN compliquée, ou si je veux savoir quels protocoles cette appli utilise ?

-   Roam utilise plusieurs protocoles différents pour communiquer avec la télé
    -   TCP (HTTP/Websockets) sur le port 8060 pour envoyer des commandes à la télé et interroger son statut
    -   Paquet magique WOL (UDP multicast vers l’adresse 255.255.255.255) pour sortir la télé du mode veille profonde
    -   RDP (UDP) sur le port 6970 pour le mode écouteurs (diffusion audio)
-   Toutes les télés Roku utilisent le port 8060 et il n’est pas possible de le changer sur la télé. Cependant, si vous avez une configuration de redirection de port et que vous souhaitez utiliser un port de sortie différent depuis Roam, c’est possible. Il suffit de saisir `[IP]:[Port]` dans le champ « Adresse IP » au lieu de simplement `[IP]`. Par exemple, entrez `192.168.8.242:8061` pour que le port `8061` soit utilisé.