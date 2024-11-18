---
hide_table_of_contents: true
---

# Roadmap Roam

## Travail Accompli pour la Prochaine Mise à Jour

- Ajout de widgets de contrôle : Play, Mute, Change Volume et Select from Control center!
- Amélioration de la gestion du champ de texte pour de nombreuses applications roku :
    - Ouverture automatique du champ de texte lorsque l'édition de texte est disponible
    - Copier, Couper, Coller depuis macOS
    - Copier, Couper, Coller + Edition généralisée sur iOS
- Meilleur reporting autour des autorisations du réseau local et de la connectivité
- Améliorations de la stabilité de la connexion

## À Venir Prochainement

-   En cours
    -   S'assurer que l'entrée de texte sur iOS ne se coupe pas en bas du clavier (comme c'est le cas actuellement)
    -   Réparer les widgets macOS
    -   Faire en sorte que iOS soit lancé sur l'App Store
        - Attendre un suivi sur l'appel
    -   Faire de meilleurs tests sur iOS et macOS pour vérifier que le système se reconnecte et reste connecté dans les scénarios suivants
        - Après une longue attente
        - Lors du retour à partir de l'arrière-plan
        - Lors de la mise sous tension de la TV à partir de l'état OFF
        - Lors de la reconnexion à internet
        - Lors du changement d'appareils

-   Ensuite : Ajouter un minuteur de mise en sourdine de +30 secondes avec décompte
    -   Tenir la touche mute pour couper le son pendant +30 secondes
    -   Cliquez à nouveau pour désactiver la sourdine et l'annuler
    -   Afficher un indicateur sous la ligne du bouton mute
        -   La barre de progression a un indicateur de progression linéaire
        -   La barre de progression a deux boutons : +30 secondes, annuler
        -   Afficher sous le panneau de boutons principal de sorte qu'il est proche de mute
    -   Rendre le +30 configurable à 30, 15, 60 options de mise en sourdine de seconde

-   Futur : Fournir une vue minimaliste optionnelle sur iOS qui réplique de près la vue de la télécommande siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Supporter également les gestes visionos...

## Idées Générales pour le Futur

-   Rédiger un article de blog sur le bot Discord et faire référence à mon MessageView
    - Rendre MessageView plus autonome
-   Rédiger un article de blog sur l'auto-traduction et la logique qui l'entoure
-   Rédiger un article de blog sur NWConnection vs URLSession pour les websockets
-   Rédiger un article de blog sur les raccourcis de clavier personnalisés
-   Rédiger un article de blog sur l'API ECP Textedit
-   Rédiger un article de blog sur les widgets du centre de contrôle

-   Créer une icône personnalisée pour la barre de menu

-   Comment faire de la voix au texte ou des commandes vocales générales ?
    - Besoin de rétro-concevoir le protocole udp de la télécommande vocale roku
    - Ou besoin d'ajouter un texte-à-parole personnalisé avec le moteur du bouton de la télécommande ?

-   Automatiser la Capture d'Écran

    -   Utiliser UITests pour obtenir des captures d'écran réelles pour toutes les tailles d'appareils + locales
    -   Utiliser AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w pour obtenir les captures d'écran dans les cadres
    -   Ou autre chose
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Essayer plus de hacks de clavier pour iPad
    -   GCKeyboard pour un
    -   FocusEnvironment pour 2
    -   S'assurer que la solution utilisée pour iOS ne casse pas l'entrée de texte dans les messages/entrée clavier

-   Tests UI
    -   Tester lorsque l'appareil est ajouté, qu'il apparaît dans le sélecteur d'appareil et est sélectionné par roam
    -   Tester que l'utilisateur peut naviguer jusqu'à paramètres -> appareils
    -   Tester que l'utilisateur peut naviguer jusqu'à paramètres -> messages
    -   Tester que l'utilisateur peut naviguer jusqu'à paramètres -> à propos
    -   Tester que l'utilisateur peut modifier/supprimer des appareils
    -   Tester que l'utilisateur peut cliquer sur les boutons une fois les appareils ajoutés
    -   Tester que l'utilisateur voit une bannière pour aucun appareil lorsqu'elle apparaît
    -   Tester que l'utilisateur voit les liens d'application
    -   Se référer au modèle de test de swiftdat pour les conteneurs de modèle
    -   Se référer ici https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad pour savoir comment configurer les tests

## Corrections de Bugs

-   Déterminer si la boucle d'appels à `nextPacket` a du sens.
    -   Au lieu de boucler toutes les 10 ms et espérer que le timing soit correct, ne devrais-je pas plutôt boucler sur les paquets reçus et tenter de les planifier à l'heure de l'hôte `10ms * globalSequenceNumber + startHostTime` et l'heure d'échantillonnage à `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Alors je peux passer d'une boucle `for await` sur l'horloge à une boucle `while !Task.isCancelled` avec un `Task.sleep` dedans.
    -   On doit donc boucler toutes les 10 ms et essayer de tirer le dernier paquet et de le programmer à ce moment là
    -   Chaque fois que nous faisons une synchronisation audio
        -   Nous avons le dernierRenderTime + un paquet de synchronisation
        -   Estimer le numéro de paquet que nous devrions envoyer + le temps de synchronisation
            -   Render Time + supplémentaire

## Améliorer la communication d'informations aux utilisateurs concernant la gestion des informations/statuts/capacités

-   Lors de la mise en marche de l'appareil avec WOL et sans connexion après 5 secondes, ou lors de la mise en marche de l'appareil et en échouant immédiatement, afficher un message d'avertissement sous le wifi
    -   “Nous n'avons pas pu réveiller votre Roku” (En savoir plus) (Ne pas afficher à nouveau pour cet appareil), (X)
    -   En savoir plus montre quelques raisons pourquoi
        -   Vous n'êtes pas connecté au même réseau (Afficher le dernier nom du réseau de l'appareil. Demander à l'utilisateur s'il est connecté à ce réseau)
        -   Votre appareil est en sommeil profond (n'a pas été mis hors tension récemment) et ne peut pas être réveillé
            -   Votre appareil ne supporte pas WWOL et est connecté à wifi
            -   Votre appareil ne supporte pas WWOL ou WOL
        -   Votre réseau n'est pas configuré de manière à nous permettre d'envoyer des commandes de réveil à l'appareil
-   Lors du clic sur un bouton désactivé, afficher une notification indiquant pourquoi il est désactivé
    -   Afficher un indicateur d'information sur le bouton pour indiquer que des informations peuvent être reçues lorsqu'il est cliqué ?
    -   Mode casque désactivé -> car l'appareil ne supporte pas le mode casque pour cette application
    -   Contrôle du volume désactivé -> car le son est diffusé via HDMI qui ne supporte pas les contrôles de volume ?
-   Lors de la numérisation active pour les appareils et qu'aucun nouveau n'est trouvé, afficher un message d'avertissement sous la liste des appareils
    -   “Nous n'avons pas pu réveiller votre Roku” (Trouver pourquoi), (X)
    -   En savoir plus affiche une popup avec quelques raisons pour lesquelles cela peut arriver
        -   Assurez-vous que votre appareil est allumé et connecté au même réseau wifi que votre application. Si cela ne fonctionne toujours pas, essayez d'ajouter l'appareil manuellement.
        -   Lien https://roam.msd3.io/manually-add-tv.md et https://support.roku.com/article/115001480188 pour plus de dépannage ou discussion
-   Ajouter un badge pour supportsWakeOnWLAN et supportsMute

## À mettre à jour lors de l'abandon du support pour iOS 17/macOS 14 (Fév 2026)

-   Aller partout et retirer les balises @available(iOS 18)
-   Utiliser les traits de prévisualisation pour injecter des données d'exemple dans les prévisualisations
-   SwiftData
    -   Utiliser le nouveau macro #Index pour les modèles
    -   Utiliser le nouveau macro #Unique pour les modèles
    -   Utiliser la suppression par lots
-   TipKit
    -   Utiliser CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
