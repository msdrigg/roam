---
hide_table_of_contents: true
---

# Feuille de route Roam

## Travail accompli pour la prochaine mise à jour

-   Ajout de widgets de contrôle : Lecture, Muet, Changer le volume et Sélectionner depuis le centre de contrôle !
-   Amélioration de la gestion des champ de texte pour de nombreuses applications roku
    -   Ouverture automatique du champ de texte lorsque l'édition de texte est disponible
    -   Copier, Couper, Coller depuis macOS (avec le clavier)
    -   Copier, Couper, Coller + Édition généralisée sur iOS
-   Meilleur rapport sur les autorisations du réseau local et la connectivité
-   Amélioration de la fonctionnalité du clavier
-   Améliorations de la stabilité de la connexion

## À venir prochainement

-   Ajoutez des options de pression longue aux touches
    -   Appui long sur la flèche droite pour avancer rapidement
    -   Appui long sur la flèche gauche pour reculer rapidement
    -   Appui long sur mute pour long-mute
        -   Rendre le +30 configurable à 30, 15, options de mute de 60 secondes
        -   Afficher la bannière avec +30 sec, x pour annuler, indicateur de progression linéaire en arrière-plan
            -   Afficher sous le panneau principal de boutons pour qu'il soit proche de mute
        -   Annule lorsque mute à nouveau (et fait également appel à l'API)
-   Réparation des widgets macOS

-   Futur : Fournir une vue minimaliste optionnelle sur iOS qui réplique de près la vue de la télécommande Siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Supporte également les gestes visionos...

## Idées générales pour le futur

-   Créez une icône de barre de menus personnalisée

-   Comment faire de la voix-à-texte ou des commandes vocales générales ?

    -   Besoin de rétro-concevoir le protocole udp de la télécommande vocale roku
    -   Ou besoin d'ajouter du texte personnalisé à la parole avec moteur de bouton distant ?

-   Automatiser la capture d'écran

    -   Utilisez UITests pour obtenir de vraies captures d'écran pour toutes les tailles de dispositifs + locales
    -   Utilisez AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w pour obtenir les captures d'écran dans les cadres
    -   Ou autre chose
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Essayez plus de hacks de clavier sur l'iPad

    -   GCKeyboard pour un
    -   FocusEnvironment pour 2
    -   Assurez-vous que la solution utilisée pour iOS ne casse pas l'entrée de texte dans les messages/l'entrée de clavier

-   Tests UI
    -   Testez quand l'appareil est ajouté qu'il apparaît dans le sélecteur d'appareil et est sélectionné par roam
    -   Testez que l'utilisateur peut naviguer vers paramètres -> appareils
    -   Testez que l'utilisateur peut naviguer vers les paramètres -> messages
    -   Testez que l'utilisateur peut naviguer vers les paramètres -> à propos
    -   Testez que l'utilisateur peut modifier/supprimer des appareils
    -   Testez que l'utilisateur peut cliquer sur des boutons une fois que les appareils sont ajoutés
    -   Testez que l'utilisateur voit une bannière pour pas d'appareils quand elle apparaît
    -   Testez que l'utilisateur voit des liens d'application
    -   Référence à swiftdat testingmodelcontainer pour modelcontainers
    -   Référence à ici https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad pour comment configurer les tests

## Corrections de bugs

-   Essayez de comprendre si la boucle d'appels à `nextPacket` a du sens.
    -   Au lieu de boucler toutes les 10ms et d'espérer que le timing est correct, devrais-je plutôt boucler sur les paquets reçus et essayer de les programmer à l'heure de l'hôte `10ms * globalSequenceNumber + startHostTime` et sampleTime à `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Ensuite, je peux passer d'une boucle `for await` sur l'horloge à une boucle `while !Task.isCancelled` avec un `Task.sleep` dedans.
    -   Donc, nous devons boucler toutes les 10 ms et essayer de retirer le dernier paquet puis de le planifier à ce moment-là
    -   Chaque fois que nous faisons une synchronisation audio
        -   Nous avons lastRenderTime + un paquet de synchronisation
        -   Estimez le numéro du paquet que nous devrions être en train d'envoyer + le temps de synchronisation
            -   Render Time + additionnel

## Améliorez la communication des informations sur la gestion de l'information/de l'état/des capacités

-   Lorsque vous allumez l'appareil avec WOL et que vous ne vous connectez pas après 5 secondes, ou lorsque vous allumez l'appareil et que vous échouez immédiatement, affichez un message d'avertissement sous le wifi
    -   « Nous n'avons pas pu réveiller votre Roku » (En savoir plus) (Ne plus afficher pour cet appareil), (X)
    -   En savoir plus montre certaines raisons pourquoi
        -   Vous n'êtes pas connecté au même réseau (Montrez le dernier nom de réseau de l'appareil. Demandez si l'utilisateur est connecté à ce réseau)
        -   Votre appareil est en veille profonde (n'a pas été éteint récemment) et ne peut pas être réveillé
            -   Votre appareil ne supporte pas le WWOL et est connecté en wifi
            -   Votre appareil ne supporte ni le WWOL ni le WOL
        -   Votre réseau n'est pas configuré de manière à nous permettre d'envoyer des commandes de réveil à l'appareil
-   Lorsque vous cliquez sur un bouton désactivé, indiquez une notification indiquant pourquoi il est désactivé
    -   Afficher un indicate d'information sur le bouton pour indiquer que des informations peuvent être reçues lorsqu'il est cliqué ?
    -   Le mode écouteurs est désactivé -> parce que l'appareil ne supporte pas le mode écouteurs pour cette application
    -   Le contrôle du volume est désactivé -> parce que le son est envoyé par HDMI qui ne supporte pas les contrôles de volume?
-   Lors de la numérisation active des appareils et qu'aucun nouveau n'est trouvé, affichez un message d'avertissement sous la liste des appareils
    -   « Nous n'avons pas pu réveiller votre Roku » (Pourquoi), (X)
    -   En savoir plus montre une popup avec certaines raisons pour lesquelles cela peut se produire
        -   Assurez-vous que votre appareil est allumé et connecté au même réseau wifi que votre application. Si cela ne fonctionne toujours pas, essayez d'ajouter l'appareil manuellement.
        -   Lien https://roam.msd3.io/manually-add-tv.md et https://support.roku.com/article/115001480188 pour plus de dépannage ou de chat
-   Ajoutez un badge pour supportsWakeOnWLAN et supportsAudioControls

## À mettre à jour lors de l'abandon du support pour iOS 17/macOS 14 (février 2026)

-   Faire le tour et enlever les balises @available(iOS 18)
-   Utiliser les traits de prévisualisation pour injecter des données d'échantillon dans les prévisualisations
-   SwiftData
    -   Utiliser le nouveau macro #Index pour les modèles
    -   Utiliser le nouveau macro #Unique pour les modèles
    -   Utiliser la suppression en batch
-   TipKit
    -   Utiliser CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
