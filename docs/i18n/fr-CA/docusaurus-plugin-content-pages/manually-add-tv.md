---
hide_table_of_contents: true
---

# Ajout manuel d'un téléviseur

1. Trouver l'adresse IP de votre téléviseur
    - Allumez votre téléviseur et allez à **Paramètres** > **Réseau** > **À propos**
    - L'adresse IP devrait ressembler à 10.x.x.x, 172.x.x.x, 173.x.x.x or 192.168.x.x
    - Cette page peut afficher une adresse "Passerelle" et une "Adresse IP". Assurez-vous de ne PAS utiliser l'adresse "Passerelle"
2. Naviguez vers les paramètres de Roam et cliquez sur "Ajouter un appareil manuellement"
3. Nommez votre appareil comme vous le souhaitez et entrez l'adresse IP de l'appareil exactement telle qu'elle est affichée sur le téléviseur Roku
4. Cliquez sur Enregistrer. Maintenant, votre Roku devrait pouvoir se connecter et fonctionner normalement

## Que faire si vous ajoutez le téléviseur manuellement et que Roam ne peut toujours pas se connecter?

Si Roam ne parvient toujours pas à contrôler votre Roku, veuillez essayer les étapes suivantes

-   Assurez-vous que votre appareil iOS est connecté au même réseau WiFi que votre téléviseur Roku
-   Assurez-vous que votre téléviseur est allumé
-   Assurez-vous que les permissions du réseau local sont activées pour Roam (ou désactivez-les et réactivez-les si elles sont déjà activées)
    -   Sur macOS : Allez à Configuration du Système -> Confidentialité et Sécurité -> Réseau Local -> Roam
    -   Sur iOS : Allez à Paramètres -> Apps -> Roam -> Réseau Local
-   Voir d'autres possibilités ici [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Que faire si j'ai une configuration réseau/VPN compliquée ? Quels protocoles cette application utilise-t-elle ?

-   Roam utilise deux protocoles différents pour communiquer avec le téléviseur
    -   TCP (HTTP/Websockets) sur le port 8060 pour envoyer des commandes au téléviseur
    -   Le paquet magique WOL (UDP multicast à l'adresse 255.255.255.255) pour réveiller le téléviseur lorsqu'il est en veille profonde
-   Tous les téléviseurs Roku utilisent le port 8060 et il n'y a aucun moyen de changer cela du côté du téléviseur. Mais si vous avez une sorte de configuration de transfert de port et que vous voulez utiliser un port sortant différent de Roam, c'est possible. Vous devez juste entrer `<IP>:<Port>` dans le champ "Adresse IP" au lieu de juste `<IP>`. Par exemple, entrez `192.168.8.242:8061` et le port choisi sera utilisé.
