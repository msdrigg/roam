---
hide_table_of_contents: true
---

# Travaux récents sur roam

# Mises à jour à venir de Roam

## Améliorations générales

-   Mettre à jour les traductions pour s'assurer qu'elles sont toutes à 100%
-   Documenter le bot de support discord et éventuellement le dupliquer dans une bibliothèque
-   Créer une icône de barre de menu personnalisée

-   Comment faire du texte-à-voix ou des commandes vocales générales?
    - Besoin de rétro-concevoir le protocole udp de la télécommande vocale roku
    - Ou bien besoin d'ajouter une conversion de texte en parole personnalisée avec le moteur de touche de télécommande?

-   Ajouter un minuteur de mise en sourdine de +30 secondes avec compte à rebours
    -   Maintenez en sourdine pour mettre en sourdine pendant +30 secondes
    -   Cliquez à nouveau pour annuler la mise en sourdine
    -   Afficher une notification de barre supérieure
        -   La barre de progression a un indicateur de progression linéaire
        -   La barre de progression a deux boutons : +30 secondes, annuler
        -   Afficher sous le panneau de boutons principal pour qu'il soit proche de la mise en sourdine
    -   Rendre le +30 configurable en 30, 15, 60 secondes d'options de mise en sourdine

-   Automatiser la capture d'écran

    -   Utiliser UITests pour obtenir des captures d'écran réelles
    -   Utiliser AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w pour obtenir les captures d'écran dans les cadres
    -   Ou autre chose
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Tester plus de hacks de clavier
    -   GCKeyboard pour l'un
    -   FocusEnvironment pour deux
    -   Veiller à ce que la solution utilisée pour iOS ne casse pas l'entrée de texte dans les messages/saisies de clavier
    
-   Implémenter iOS 18 AppIntents
    -   Ajouter des intentions d'application au centre de contrôle
        -   Utiliser le basculement pour mettre en sourdine/mettre le son et allumer/éteindre
        -   Utiliser des boutons pour tout le reste
        -   Utiliser le violet correct pour la teinte
        -   Rendre configurable comme les widgets
        -   Faire fonctionner avec un indice d'action
    -   Permettre à siri/spotlight de mieux voir les choses dans mon application de quelque façon que ce soit?
        -   Ajouter des liens universels aux appareils pour que siri puisse y faire un lien?
        -   Veiller à ce que la recherche sémantique fonctionne
        -   Implémenter transferrable via string/codeable pour mes entités d'application
            -   ProxyRepresentation
            -   CodableRepresentation
-   Fournir une vue minimaliste optionnelle sur iOS qui reproduit de près la vue de la télécommande de siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Supporter également les gestes de visionos...
    -   Besoin de construire l'api d'édition de texte en premier
-   Ajouter un suivi d'événements sur les actions que les utilisateurs font réellement sur leurs appareils (se connecter à firebase analytics peut-être?)
    -   Suivre qui utilise la vue minimaliste, quelles actions ils font, etc...

## Correctifs de bugs

-   Déterminer si la boucle des appels à `nextPacket` a du sens.
    -   Au lieu de boucler toutes les 10ms et espérer que le timing est correct, devrais-je plutôt boucler sur les paquets reçus et essayer de les planifier à l'heure de l'hôte `10ms * globalSequenceNumber + startHostTime` et sampleTime à `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Ensuite, je peux passer d'une boucle `for await` sur l'horloge à une boucle `while !Task.isCancelled` avec un `Task.sleep` dedans.
    -   D'accord, donc nous avons besoin de boucler toutes les 10 ms et d'essayer de récupérer le dernier paquet et de l'organiser à ce moment-là
    -   Chaque fois que nous faisons une synchronisation audio
        -   Nous avons le dernier temps de rendu + un paquet de synchronisation
        -   Estimer le numéro de paquet que nous devrions envoyer + le temps de synchronisation
            -   Temps de rendu + supplément

## Améliorer les tests

-   Tests UI
    -   Tester quand un appareil est ajouté qu'il apparaît dans le sélecteur d'appareils et est sélectionné par roam
    -   Tester que l'utilisateur peut naviguer vers les paramètres -> appareils
    -   Tester que l'utilisateur peut naviguer vers les paramètres -> messages
    -   Tester que l'utilisateur peut naviguer vers les paramètres -> à propos
    -   Tester que l'utilisateur peut éditer/supprimer des appareils
    -   Tester que l'utilisateur peut cliquer sur les boutons une fois que les appareils sont ajoutés
    -   Tester que l'utilisateur voit une bannière pour aucun appareil quand elle apparaît
    -   Tester que l'utilisateur voit des applications de liens
    -   Se référer à swiftdat testingmodelcontainer pour les conteneurs de modèle
    -   Se référer ici https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad pour savoir comment configurer les tests

## Clip d'application

-   AppClip
    -   Ajouter un bouton "getAShareableLinkToThisDevice" sur les paramètres -> appareil
        -   Pré-générer tous les 1.1M codes de clip d'application et coder les emplacements des anneaux (0.5GB)
        -   Créer un bouton pour "Obtenir un lien partageable vers l'appareil!" avec une prévisualisation d'image du code de clip d'application (couleur roam)
        -   Télécharger le code + lien et le convertir en PNG sur l'appareil lorsque la position d'un appareil est modifiée
        -   Faire en sorte que le code ouvre l'appareil comme un lien partagé vers une image (avec prévisualisation!)
    -   Faire également en sorte que le lien réel de l'appareil soit partageable

## Améliorer la messagerie utilisateur autour de la gestion de l'info/statut

-   Mettre à jour la gestion de l'info/statut pour mieux gérer l'état volatile
    -   À la déconnexion, sélectionnez, cliquez sur le bouton, passez au premier plan, ouvrez l'application -> Redémarrez la boucle de reconnexion si déconnecté
    -   La boucle de reconnexion consiste à essayer de manière exponentielle de renouer des connexions en échec (0.5s, double, 10s de backoff)
    -   Lorsqu'on est connecté à l'appareil, désactiver toujours les avertissements de réseau
    -   Lorsqu'on essaye de se connecter à l'appareil, ou d'allumer l'appareil, montrer une icône d'information en rotation au lieu du point gris
    -   Lorsqu'on allume l'appareil et qu'on réussit, montrer une animation lors de la transition du gris -> rotation -> vert
    -   Lorsqu'on allume l'appareil avec un WOL et qu'on ne se connecte pas après 5 secondes, ou qu'on allume l'appareil et qu'on échoue immédiatement, montrer un message d'avertissement sous celui du wifi
        -   “Nous n'avons pas réussi à réveiller votre Roku” (En savoir plus) (Ne plus afficher pour cet appareil), (X)
        -   En savoir plus montre quelques raisons pour lesquelles
            -   Vous n'êtes pas connecté au même réseau (Affiche le dernier nom de réseau de l'appareil. Demande si l'utilisateur est connecté à ce réseau)
            -   Votre appareil est en veille profonde (n'a pas été mis hors tension récemment) et ne peut pas être réveillé
                -   Votre appareil ne supporte pas le WWOL et est connecté au wifi
                -   Votre appareil ne supporte pas le WWOL ou le WOL
            -   Votre réseau n'est pas configuré de manière à nous permettre d'envoyer des commandes de réveil à l'appareil
    -   Boucle de reconnexion = Tenter de manière exponentielle de renouer la connexion à la reconnexion ECP
        -   Reconnecter d'abord l'ECP
        -   Ecoutez la notification en second
            -   Gérer +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   S'assurer que nous pouvons gérer chacune de ces demandes et leur format…
        -   Rafraîchir l'état de l'appareil en troisième
        -   Rafraîchir l'état de la requête-textedit en quatrième
            -   Mettre à jour l'état de la création de texte
        -   Rafraîchir les icônes de l'appareil en cinquième
    -   Sur tous les changements après reconnexion (par notification ou autre)
        -   Mettre à jour l'appareil (stocké) et l'état de l'appareil (volatile)
    -   Après réconnection/déconnexion, mettre à jour le statut en ligne dans la vue à distance

## Améliorer la messagerie utilisateur autour des capacités des appareils

-   Mettre à jour la messagerie utilisateur lorsque des erreurs peuvent se produire
    -   Lorsqu'on clique sur un bouton désactivé, ouvrir une fenêtre contextuelle pour montrer pourquoi il est désactivé
        -   Montrer un indicateur d'information sur le bouton pour indiquer qu'information peut être reçue lorsqu'on y clique ?
        -   Mode écouteurs désactivé -> parce que l'appareil ne supporte pas le mode écouteurs pour cette application
        -   Contrôle du volume désactivé -> parce que l'audio est mis en sortie sur HDMI ce qui ne supporte pas les contrôles de volume?
    -   Lors de la recherche active d'appareils et qu'aucun nouveau n'est trouvé, montrer un message d'avertissement sous la liste des appareils
        -   “Nous n'avons pas réussi à réveiller votre Roku” (Trouver pourquoi), (X)
        -   En savoir plus montre une fenêtre contextuelle avec quelques raisons pour lesquelles cela peut arriver
            -   Assurez-vous que votre appareil est allumé et connecté au même réseau wifi que votre application. Si cela ne fonctionne toujours pas, essayez d'ajouter l'appareil manuellement.
            -   Lien https://roam.msd3.io/manually-add-tv.md et https://support.roku.com/article/115001480188 pour plus de dépannage ou de chat
-   Ajouter un badge pour supportsWakeOnWLAN et supportsMute

## Support ecp textedit

-   Mettre à jour la gestion du clavier pour supporter ecp-textedit sur `KeyboardEntry`
    -   Afficher le clavier lorsque le texte est ouvert
    -   Masquer le clavier lorsque le texte est fermé
    -   Tester que le collage + sélection/suppression dans le champ d'édition de texte fonctionne comme prévu
    -   Si ecp-textedit est supporté, permettre la sélection, la suppression de texte et le déplacement du curseur. Il suffit de renvoyer le texte chaque fois qu'il change si c'est supporté.
    -   Si ecp-textedit n'est pas supporté, revenir à l'envoi de touches
    -   Sur macOS, montrer un indicateur lorsque le texte est activé 
    -   Sur macOS, permettre cmd+v et cmd+c et cmd+x pour copier-coller de/vers le tampon

Commandes de session ECP du clavier (notes)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## À mettre à jour lors de l'abandon du support pour iOS 17/macOS 15 (2025)

-   Utiliser les traits de prévisualisation pour injecter des données d'exemple dans les prévisualisations
    -   Comment faire cela avec iOS 17 toujours en jeu ?
    -   Comment utiliser @Previewable dans les prévisualisations avec iOS 17 toujours en jeu ??
-   SwiftData
    -   Utiliser le nouveau macro #Index pour les modèles
    -   Utiliser le nouveau macro #Unique pour les modèles
    -   Utiliser la suppression en lot
-   TipKit
    -   Utiliser CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698

