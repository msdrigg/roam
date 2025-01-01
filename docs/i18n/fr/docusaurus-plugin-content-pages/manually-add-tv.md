---
hide_table_of_contents: true
---

# Ajout manuel d'un téléviseur

1. Trouvez l'adresse IP de votre téléviseur
    - Allumez votre téléviseur et allez dans **Paramètres** > **Réseau** > **À propos**
    - L'adresse IP doit ressembler à 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Cette page peut afficher une adresse "Passerelle" et une "Adresse IP". Assurez-vous de NE PAS utiliser l'adresse "Passerelle"
2. Accédez aux paramètres de Roam et cliquez sur "Ajouter un appareil manuellement"
3. Nommez votre appareil comme vous le souhaitez et entrez l'adresse IP exacte telle qu'affichée sur le téléviseur Roku
4. Cliquez sur Enregistrer. Votre Roku devrait maintenant être capable de se connecter et de fonctionner normalement

## Que faire si vous ajoutez manuellement le téléviseur et que Roam ne peut toujours pas se connecter ?

Si Roam ne peut toujours pas contrôler votre Roku, veuillez essayer les étapes suivantes

-   Assurez-vous que votre appareil iOS est connecté au même réseau WiFi que votre téléviseur Roku
-   Assurez-vous que votre téléviseur est allumé
-   Assurez-vous que les autorisations de réseau local sont activées pour Roam (ou désactivez et réactivez-les si elles sont déjà activées)
    -   Sur macOS : Allez dans Paramètres du système -> Confidentialité et sécurité -> Réseau local -> Roam
    -   Sur iOS : Allez dans Paramètres -> Applications -> Roam -> Réseau local
-   Consultez les autres possibilités ici [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## Que faire si j'ai une configuration réseau/VPN compliquée ? Quels protocoles cette application utilise-t-elle ?

-   Roam utilise deux protocoles différents pour communiquer avec le téléviseur
    -   TCP (HTTP/Websockets) sur le port 8060 pour envoyer des commandes au téléviseur
    -   WOL magic packet (multidiffusion UDP à l'adresse 255.255.255.255) pour réveiller le téléviseur en veille profonde
-   Tous les téléviseurs Roku utilisent le port 8060 et il n'y a aucun moyen de changer cela du côté du téléviseur. Mais si vous avez une configuration de transfert de port et souhaitez utiliser un port sortant différent de Roam, c'est possible. Vous devez juste entrer `<IP>:<Port>` dans le champ "Adresse IP" au lieu de simplement `<IP>`. Par exemple, entrez `192.168.8.242:8061` et le port choisi sera utilisé.