---
hide_table_of_contents: true
---

# Plan de route Roam

## Travaux terminés pour la prochaine mise à jour

-   Ajout de widgets de contrôle : Lecture, Muet, Changer le volume et Sélection depuis le centre de contrôle !
-   Amélioration du traitement du champ de texte pour de nombreuses applications roku
    -   Ouverture automatique du champ de texte lorsque l'édition du texte est disponile
    -   Copier, Couper, Coller depuis macOS (avec le clavier)
    -   Copier, Couper, Coller + Édition généralisée sur iOS
-   Meilleur reporting autour des autorisations de réseau local et de la connectivité
-   Amélioration de la fonctionnalité du clavier
-   Améliorations de la stabilité de la connexion

## À venir bientôt

-   Ajout d'options de pression longue aux touches
    -   Appui long sur la flèche droite pour avancer rapide
    -   Appui long sur la flèche gauche pour reculer rapide
    -   Appui long sur la touche mute pour un mute longue durée
        -   Rendre le +30 configurable à 30, 15, 60 options de mute de secondes
        -   Afficher une bannière avec +30 sec, x pour annuler, indicateur de progression linéaire en arrière-plan
            -   Montrer sous le panneau principal de bouton afin qu'il soit proche du mute
        -   Annule lors de la mise en sourdine à nouveau (et effectue également un appel api)
-   Syx macOS widgets

-   Futur : fournir une vue minimaliste optionnelle sur iOS qui reproduit de près la vue de la télécommande siri 
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Support visionos gestures as well...

## Idées générales pour le futur

-   Créer une icône de barre de menu personnalisée

-   Comment faire de la voix au texte ou des commandes vocales générales ?

    -   Besoin d'ingénierie inverse du protocole udp de la télécommande vocale roku
    -   Ou besoin d'ajouter un texte personnalisé à la parole avec le moteur de bouton de télécommande ?

-   Automatiser la capture d'écran

    -   Utiliser UITests pour obtenir de véritables captures d'écran pour toutes les tailles d'appareils + locales
    -   Utiliser AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w pour obtenir les captures d'écran dans les cadres
    -   Ou autre chose
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Essayer plus de hacks de clavier sur iPad

    -   GCKeyboard pour un
    -   FocusEnvironment pour deux
    -   S'assurer que la solution utilisée pour iOS ne brise pas l'entrée de texte dans les messages/entrée de clavier

-   Tests d'interface utilisateur
    -   Tester lorsqu'un appareil est ajouté qu'il apparaît dans le choix d'appareil et est sélectionné par roam
    -   Tester que l'utilisateur peut accéder aux paramètres -> appareils
    -   Tester que l'utilisateur peut accéder à paramètres -> messages
    -   Tester que l'utilisateur peut accéder aux paramètres -> à propos
    -   Tester que l'utilisateur peut modifier/supprimer des appareils
    -   Tester que l'utilisateur peut cliquer sur des boutons une fois que les appareils sont ajoutés
    -   Tester que l'utilisateur voit une bannière pour aucun appareil lorsqu'elle apparaît
    -   Tester que l'utilisateur voit des liens applicatifs
    -   Se référer à la swiftdat testingmodelcontainer for modelcontainers
    -   Se référer ici pour savoir comment configurer les tests https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad 

## Corrections de bugs

-   Vérifier si la boucle d'appels à `nextPacket` est logique.
    -   Au lieu de boucler toutes les 10ms et espérer que le timing soit correct, devrais-je plutôt boucler sur les paquets reçus et essayer de les programmer à l'heure de l'hôte `10ms * globalSequenceNumber + startHostTime` et sampleTime à `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Alors je peux passer d'une boucle `for await` sur l'horloge à une boucle `while !Task.isCancelled` avec un `Task.sleep` dedans.
    -   Donc, nous avons besoin de boucler toutes les 10 ms et d'essayer de sortir le dernier paquet puis de le programmer à ce moment-là
    -   Chaque fois que nous faisons une synchronisation audio
        -   Nous avons lastRenderTime + un paquet de synchronisation
        -   Estimer le numéro de paquet que nous devrions envoyer à + l'heure de synchronisation
            -   Render Time + additional

## Améliorer la communication de l'utilisateur autour de la gestion de l'information/du statut/des capacités

-   Lors de la mise sous tension de l'appareil avec WOL et non connecté après 5 secondes, ou lors de la mise sous tension de l'appareil et de l'échec immédiat, afficher un message d'avertissement sous le wifi un
    -   “Nous n'avons pas pu réveiller votre Roku” (En savoir plus) (Ne plus afficher pour cet appareil), (X)
    -   En savoir plus montre certaines raisons pour lesquelles
        -   Vous n'êtes pas connecté au même réseau (Afficher le dernier nom de réseau de l'appareil. Demander à l'utilisateur s'il est connecté à ce réseau)
        -   Votre appareil est en veille profonde (n'a pas été éteint récemment) et ne peut pas être réveillé
            -   Votre appareil ne supporte pas le WWOL et est connecté au wifi
            -   Votre appareil ne supporte ni le WWOL ni le WOL
        -   Votre réseau n'est pas configuré de manière à nous permettre d'envoyer des commandes de réveil à l'appareil
-   Lors de l'appui sur un bouton désactivé, afficher une notification indiquant pourquoi il est désactivé
    -   Afficher un indicateur d'information sur le bouton pour indiquer que des informations peuvent être reçues lorsqu'il est cliqué ?
    -   Mode écouteurs désactivé -> car l'appareil n'accepte pas le mode écouteurs pour cette application
    -   Contrôle du volume désactivé -> car l'audio est transmis par HDMI qui ne supporte pas les contrôles de volume ?
-   Lors de la recherche active d'appareils et qu'aucun nouveau n'est trouvé, afficher un message d'avertissement sous la liste d'appareils
    -   “Nous n'avons pas pu réveiller votre Roku” (Découvrez pourquoi), (X)
    -   En savoir plus montre une popup avec quelques raisons pour lesquelles ceci pourrait se produire
        -   Assurez-vous que votre appareil est allumé et connecté au même réseau wifi que votre application. Si cela ne fonctionne toujours pas, essayez d'ajouter l'appareil manuellement.
        -   Lien https://roam.msd3.io/manually-add-tv.md et https://support.roku.com/article/115001480188 pour plus de dépannage ou de chat
-   Ajouter un badge pour supportsWakeOnWLAN et supportsAudioControls

## À mettre à jour lorsque l'on abandonne le support pour iOS 17/macOS 14 (février 2026)

-   Parcourir et supprimer les tags @available(iOS 18)
-   Utiliser les traits de prévisualisation pour injecter des données d'exemple dans les prévisualisations
-   SwiftData
    -   Utiliser le nouveau macro #Index pour les modèles
    -   Utiliser le nouveau macro #Unique pour les modèles
    -   Utiliser une suppression par lots
-   TipKit
    -   Utiliser CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
