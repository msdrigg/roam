---
hide_table_of_contents: true
---

# Plan d'action de Roam

## Travail terminé pour la prochaine mise à jour

- Ajout de widgets de contrôle : Jouer, Muet, Changer le volume et Sélectionner depuis le centre de contrôle!
- Amélioration de la gestion des champs de texte pour de nombreuses applications roku 
    - Ouverture automatique du champ de texte lorsque l'édition de texte est disponible
    - Copier, Couper, Coller à partir de macOS
    - Copier, Couper, Coller + Édition généralisée sur iOS
- Amélioration des rapports sur les permissions du réseau local et la connectivité
- Améliorations de la stabilité de la connexion

## À venir

-   En cours
    -   Assurez-vous que la saisie de texte sur iOS ne coupe pas en dessous du clavier (comme c'est le cas actuellement)
    -   Corrigez les widgets macOS
    -   Faire publier la version iOS sur l'App Store
        - Attendre le suivi de l'appel
    -   Faire des tests plus poussés sur iOS et macOS pour tester que le système se reconnecte et reste connecté dans les scénarios suivants
        - Après avoir attendu longtemps
        - Lorsqu'on revient du fond
        - Lorsque la TV est allumée depuis l'état OFF
        - Lors de la reconnexion à Internet
        - Lors du changement de dispositifs

-   Prochaine étape : ajouter un minuteur de mise en sourdine de +30 secondes avec compte à rebours
    -   Maintenez Mute pour mettre en sourdine pendant +30 secondes
    -   Cliquez à nouveau pour désactiver le mode muet et l'annuler
    -   Afficher un indicateur sous la ligne du bouton de mise en sourdine 
        -   La barre de progression a un indicateur de progression linéaire
        -   La barre de progression a deux boutons : +30 secondes, annuler
        -   Afficher sous le panel principal des boutons pour qu'il soit proche de mute
    -   Rendre le +30 configurable pour des options de mise en sourdine de 30, 15, 60 secondes

-   Futur: Fournir une vue optionnelle minimaliste sur iOS qui reproduit de près la vue de la télécommande siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Supporter les gestes visionos également...

## Idées générales pour le futur

-   Rédiger un article de blog sur le bot discord et pointer vers mon MessageView
    - Rendre messageView plus autonome
-   Rédiger un article de blog sur l'auto-traduction et la logique qui l'accompagne
-   Rédiger un article de blog sur NWConnection vs URLSession pour websockets
-   Rédiger un blog sur les raccourcis de clavier personnalisés
-   Rédiger un blog sur l'API ECP Textedit
-   Rédiger un blog sur les widgets du centre de contrôle

-   Créer une icône personnalisée pour la barre de menu

-   Comment faire de la voix-à-texte ou des commandes vocales générales?
    - Besoin de rétroconcevoir le protocole udp de la télécommande vocale roku
    - Ou besoin d'ajouter du texte personnalisé à la parole avec le moteur de bouton de télécommande?

-   Automatiser la capture d'écran

    -   Utiliser UITests pour obtenir réellement des captures d'écran pour toutes les tailles de dispositifs + locales
    -   Utiliser AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w pour obtenir les captures d'écran dans les cadres
    -   Ou autre chose
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Essayez plus de hacks de clavier pour iPad
    -   GCKeyboard pour un
    -   FocusEnvironment pour 2
    -   S'assurer que la solution utilisée pour iOS ne casse pas la saisie de texte dans les messages/saisie de clavier

-   Tests d'IU
    -   Testez lorsqu'un dispositif est ajouté qu'il apparaisse dans le sélecteur de dispositifs et est sélectionné par roam
    -   Testez que l'utilisateur peut naviguer vers les paramètres -> dispositifs
    -   Testez que l'utilisateur peut naviguer vers les paramètres -> messages
    -   Testez que l'utilisateur peut naviguer vers les paramètres -> à propos
    -   Testez que l'utilisateur peut éditer/supprimer des dispositifs
    -   Testez que l'utilisateur peut cliquer sur les boutons une fois que les dispositifs sont ajoutés
    -   Testez que l'utilisateur voit la bannière pour aucun dispositif quand elle apparaît
    -   Testez que l'utilisateur voit les applinks
    -   Référez-vous au testingmodelcontainer swiftdat pour modelcontainers
    -   Référez-vous ici https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad pour savoir comment configurer les tests

## Correctifs

-   Découvrez si la boucle d'appels à `nextPacket` a du sens.
    -   Au lieu de boucler toutes les 10 ms et d'espérer que le timing est correct, devrais-je plutôt parcourir les paquets reçus et essayer de les planifier à l'heure hôte `10ms * globalSequenceNumber + startHostTime` et sampleTime à `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Ensuite, je peux passer d'une boucle `for await` sur l'horloge à une boucle `while !Task.isCancelled` avec un `Task.sleep` dedans.
    -   D'accord, nous avons besoin de boucler toutes les 10 ms et d'essayer de retirer le dernier paquet et ensuite de le planifier à ce moment-là
    -   Chaque fois que nous faisons une synchronisation audio
        -   Nous avons lastRenderTime + un paquet de synchronisation
        -   Estimez le numéro de paquet que nous devrions envoyer à + l'heure de synchronisation
            -   Heure de rendu + supplémentaire

## Améliorer les messages d'information de l'utilisateur autour de la gestion de l'information/du statut/des capacités

-   Lors de l'allumage de l'appareil avec WOL et de la non connexion après 5 secondes, ou lors de l'allumage de l'appareil et de l'échec immédiat, afficher un message d'avertissement sous celui du wifi
    -   “Nous n'avons pas pu réveiller votre Roku” (En savoir plus) (Ne plus afficher pour cet appareil), (X)
    -   En savoir plus montre quelques raisons pour lesquelles
        -   Vous n'êtes pas connecté au même réseau (Afficher le dernier nom de réseau de l'appareil. Demander à l'utilisateur s'il est connecté à ce réseau)
        -   Votre appareil est en veille prolongée (n'a pas été éteint récemment) et ne peut pas être réveillé
            -   Votre appareil ne supporte pas le WWOL et est connecté au wifi
            -   Votre appareil ne supporte pas le WWOL ou le WOL
        -   Votre réseau n'est pas configuré de manière à nous permettre d'envoyer des commandes de réveil à l'appareil
-   Lorsque vous cliquez sur un bouton désactivé, affichez une notification indiquant pourquoi il est désactivé
    -   Afficher un indicateur d'information sur le bouton pour indiquer que des informations peuvent être reçues lorsqu'on clique dessus ?
    -   Mode écouteur désactivé -> parce que l'appareil ne supporte pas le mode écouteur pour cette application
    -   Contrôle du volume désactivé -> parce que l'audio est diffusé sur HDMI qui ne supporte pas les contrôles du volume ?
-   Lorsque vous scannez activement des appareils et que vous n'en trouvez pas de nouveaux, affichez un message d'avertissement sous la liste des appareils
    -   “Nous n'avons pas pu réveiller votre Roku” (Savoir pourquoi), (X)
    -   En savoir plus montre une popup avec quelques raisons pour lesquelles cela peut se produire
        -   Assurez-vous que votre appareil est allumé et connecté au même réseau wifi que votre application. Si cela ne fonctionne toujours pas, essayez d'ajouter l'appareil manuellement.
        -   Lien https://roam.msd3.io/manually-add-tv.md et https://support.roku.com/article/115001480188 pour plus de dépannage ou de chat
-   Ajouter un badge pour supportsWakeOnWLAN et supportsMute

## À mettre à jour lorsque le support pour iOS 17/macOS 14 sera abandonné (Février 2026)

-   Faire le tour et enlever les balises @available(iOS 18)
-   Utiliser les caractéristiques de prévisualisation pour injecter des données d'échantillon dans les prévisualisations
-   SwiftData
    -   Utiliser le nouveau macro #Index pour les modèles
    -   Utiliser le nouveau macro #Unique pour les modèles
    -   Utiliser la suppression par lots
-   TipKit
    -   Utilisez CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698