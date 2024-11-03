---
hide_table_of_contents: true
---

# Travail récent le plus sur Roam

# Prochaines mises à jour de Roam

- Widgets de contrôle ajoutés : Play, Mute, Change Volume et Select depuis le centre de contrôle !

## Feuille de route

-   Mise à jour de la gestion du clavier pour supporter ecp-textedit sur `KeyboardEntry`
    -   Afficher le clavier lorsque textedit est ouvert
    -   Masquer le clavier lorsque textedit est fermé
    -   S'assurer que le collage + la sélection/suppression dans le champ textedit fonctionne comme prévu
    -   Utiliser le champ de texte modifié actuel si ecp-textedit n'est pas supporté, utiliser le champ de texte standard si c'est le cas
    -   Sur macOS, support de la pâte avec cmdP, copier/couper avec cmdX + cmdC
    -   Si ecp-textedit n'est pas pris en charge, revenir au comportement actuel d'envoi de clés
    -   Sur macOS, afficher un champ de texte en bas lorsque textedit est activé 
    -   Sur macOS, permettre cmd+v et cmd+c et cmd+x pour copier/coller depuis/vers le buffer

-   Ajouter une minuterie de silence de +30 secondes avec compte à rebours
    -   Maintenir le silence pour rendre muet pendant +30 secondes
    -   Cliquer à nouveau pour désactiver le silence et l'annuler
    -   Montrer un indicateur sous la ligne du bouton de silence 
        -   La barre de progression a un indicateur de progression linéaire
        -   La barre de progression a deux boutons : +30 secondes, annuler
        -   Afficher en dessous du panneau principal de boutons pour qu'il soit près de la sourdine
    -   Rendre le +30 configurable à 30, 15, 60 options de silence en secondes

-   Fournir une vue Minimaliste facultative sur iOS qui reproduit de près la vue du siri remote
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Supporter les gestes visionos aussi...

## Idées Générales pour le futur

-   Écrire un article de blog à propos du bot discord et pointer vers mon MessageView
-   Écrire un article de blog à propos de la traduction automatique et de la logique autour de celle-ci

-   Créer une icône de barre de menu personnalisée

-   Comment faire de la voix-au-texte ou des commandes vocales générales ?
    - Il faudra rétro-ingénier le protocole udp de la télécommande vocale roku
    - Ou faudra-t-il ajouter un texte personnalisé à la parole avec le moteur de bouton de télécommande ?

-   Automatiser la Capture de captures d'écran

    -   Utilisez UITests pour obtenir des captures d'écran réelles
    -   Utilisez AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w pour obtenir les captures d'écran dans les cadres
    -   Ou autre chose
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Tester plus de hacks de clavier
    -   GCKeyboard pour l'un
    -   FocusEnvironment pour 2
    -   Assurez-vous que la solution utilisée pour iOS ne casse pas la saisie de texte dans les messages/l'entrée du clavier

-   Ajouter un suivi des événements sur les actions que les utilisateurs font réellement sur leurs appareils (se connecter à l'analytique firebase peut-être ?)
    -   Suivre qui utilise la vue minimaliste, quelles actions ils font, etc...

## Corrections de bugs

-   Déterminer si la boucle d'appels à `nextPacket` est logique.
    -   Au lieu de boucler toutes les 10ms et d'espérer que le timing est correct, devrais-je au contraire parcourir les paquets reçus et essayer de les planifier à l'heure d'hôte `10ms * globalSequenceNumber + startHostTime` et sampleTime à `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Ensuite, je peux passer d'une boucle `for await` sur l'horloge à une boucle `while !Task.isCancelled` avec un `Task.sleep` dedans.
    -   D'accord, donc nous devons boucler toutes les 10 ms et essayer de retirer le dernier paquet et ensuite le planifier à ce moment-là
    -   Chaque fois que nous faisons une synchronisation audio
        -   Nous avons le dernier temps de rendu + un paquet de synchronisation
        -   Estimer le numéro de paquet que nous devrions envoyer à + l'heure de synchronisation
            -   Temps de rendu + supplémentaire

## Améliorer les tests

-   Tests UI
    -   Tester quand un appareil est ajouté qu'il apparait dans le sélecteur d'appareil et est sélectionné par roam
    -   Tester que l'utilisateur peut naviguer vers les paramètres -> appareils
    -   Tester que l'utilisateur peut naviguer vers les paramètres -> messages
    -   Tester que l'utilisateur peut naviguer vers les paramètres -> à propos
    -   Tester que l'utilisateur peut modifier/supprimer des appareils
    -   Tester que l'utilisateur peut cliquer sur les boutons une fois que les appareils sont ajoutés
    -   Tester que l'utilisateur voit la bannière pour "aucun appareil" quand elle apparait
    -   Tester que l'utilisateur voit les liens d'application
    -   Se référer à swiftdat testingmodelcontainer pour les conteneurs de modèles
    -   Se référer ici https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad pour savoir comment configurer les tests

## App Clip

-   AppClip
    -   Ajouter un bouton "getAShareableLinkToThisDevice" sur les paramètres -> appareil
        -   Pré-générer tous les 1.1M codes app clip et coder les localisations en anneaux (0.5GB)
        -   Faire un bouton pour "Obtenir un lien partageable vers l'appareil !" avec une prévisualisation d'image vers le code app clip (couleur de roam)
        -   Télécharger le code + le lien et le convertir en PNG sur l'appareil lorsqu'une localisation d'appareil est modifiée
        -   Avoir le code ouvrir l'appareil comme un lien partagé vers une image (avec prévisualisation !)
    -   Rendre également le lien de l'appareil réellement partageable

## Améliorer la messagerie utilisateur autour de la gestion de l'information/du statut

-   Mettre à jour la gestion de l'information/du statut pour mieux gérer l'état volatile
    -   En cas de déconnexion, de sélection, de clic sur un bouton, de passage au premier plan, d'ouverture de l'application -> Redémarrer la boucle de reconnexion en cas de déconnexion
    -   La boucle de reconnexion consiste à essayer de manière exponentielle des connexions échouées (0,5s, double, 10s de recul)
    -   Lorsque connecté à l'appareil, désactiver toujours les avertissements de réseau
    -   Lors de la tentative de connexion à l'appareil, ou de la mise en marche de l'appareil, montrer une icône d'information qui tourne au lieu d'un point gris
    -   Lors de la mise en marche de l'appareil et de la réussite, montrer une animation lors de la transition de gris -> spinning -> vert
    -   Lors de la mise en marche de l'appareil avec WOL et non connecté après 5 secondes, ou lors de la mise en marche de l'appareil et échec immédiat, montrer un message d'avertissement en dessous de l'avertissement wifi
        -   "Nous n'avons pas pu réveiller votre Roku" (En savoir plus) (Ne plus montrer pour cet appareil), (X)
        -   En savoir plus montre quelques raisons pourquoi
            -   Vous n'êtes pas connecté au même réseau (Montrer le dernier nom de réseau de l'appareil. Demander à l'utilisateur s'il est connecté à ce réseau)
            -   Votre appareil est en dormance profonde (n'a pas été éteint récemment) et ne peut être réveillé
                -   Votre appareil ne supporte pas WWOL et est connecté au wifi
                -   Votre appareil ne supporte pas WWOL ou WOL
            -   Votre réseau n'est pas configuré de manière à nous permettre d'envoyer des commandes de réveil à l'appareil
    -   Boucle de reconnexion = Essayer de reconnecter ECP de manière exponentielle
        -   Reconnecter ECP d'abord
        -   Écouter notifier en deuxième lieu
            -   Gérer +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   S'assurer que nous pouvons gérer chacune de ces demandes et leur format…
        -   Rafraîchir l'état de l'appareil en troisième lieu
        -   Rafraîchir le texte d'interrogation-état-textedit en quatrième lieu
            -   Mettre à jour l'état du texte d'édition
        -   Rafraîchir les icônes de l'appareil en cinquième lieu
    -   Sur tous les changements après reconnexion (par le biais de notify ou autre)
        -   Mettre à jour l'appareil (stocké) et l'état de l'appareil (volatile)
    -   Après reconnexion/déconnexion, mettre à jour le statut en ligne dans la vue à distance

## Améliorer la communication aux utilisateurs autour des capacités de l'appareil

-   Mettre à jour la communication aux utilisateurs lorsque des erreurs peuvent survenir
    -   Lorsque vous cliquez sur un bouton désactivé, ouvrez une popover pour montrer pourquoi il est désactivé
        -   Montrer un indicateur d'information sur le bouton pour indiquer que des informations peuvent être reçues lorsqu'il est cliqué ?
        -   Mode Casque désactivé -> parce que l'appareil ne supporte pas le mode casque pour cette application
        -   Contrôle du volume désactivé -> parce que l'audio est en sortie par HDMI qui ne supporte pas les commandes de volume ?
    -   Lors de la recherche active d'appareils et qu'aucun nouveau n'est trouvé, afficher un message d'avertissement en dessous de la liste des appareils
        -   "Nous n'avons pas pu réveiller votre Roku" (Découvrir pourquoi), (X)
        -   Découvrir plus montre une pop-up avec certaines raisons pour lesquelles cela peut se produire
            -   Assurez-vous que votre appareil est allumé et connecté au même réseau wifi que votre application. Si cela ne fonctionne toujours pas, essayez d'ajouter l'appareil manuellement.
            -   Lien https://roam.msd3.io/manually-add-tv.md et https://support.roku.com/article/115001480188 pour plus de dépannage ou de chat
-   Ajouter un badge pour supportsWakeOnWLAN et supportsMute

## Notes ECP textedit

Commands de session ECP de clavier (notes)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## À mettre à jour lors de l'abandon du support pour iOS 17/macOS 14 (Février 2026)

-   Faire le tour et enlever les balises @available(iOS 18)
-   Utiliser les attributs de prévisualisation pour insérer des données d'échantillon dans les prévisualisations
    -   Comment faire cela avec l'iOS 17 toujours en jeu ?
    -   Comment utiliser @Previewable dans les aperçus avec l'iOS 17 toujours en jeu ??
-   SwiftData
    -   Utiliser le nouveau #Index macro pour les modèles
    -   Utiliser le nouveau #Unique macro pour les modèles
    -   Utiliser la suppression par lots
-   TipKit
    -   Utiliser CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
