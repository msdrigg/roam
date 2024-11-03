---
hide_table_of_contents: true
---

# Les travaux Roam les plus récents

# Prochaines mises à jour de Roam

## Améliorations générales

-   Mettre à jour les traductions pour s'assurer que toutes sont à 100%
-   Documenter le bot de support discord et peut-être le dupliquer en une bibliothèque
-   Créer une icône de barre de menu personnalisée

-   Comment faire une transcription vocale ou des commandes vocales générales?
    - Besoin de rétro-ingénierie du protocol UDP de la télécommande vocale Roku
    - Ou besoin d'ajouter du texte personnalisé à la parole avec le moteur du bouton de télécommande?

-   Ajouter une minuterie de sourdine de +30 secondes avec compte à rebours
    -   Maintenir en sourdine pour mettre en sourdine pendant +30 secondes
    -   Cliquez à nouveau pour annuler la sourdine
    -   Afficher une notification de barre supérieure
        -   La barre de progression a un indicateur de progression linéaire
        -   La barre de progression a deux boutons : +30 secondes, annuler
        -   Afficher sous le panneau de bouton principal pour qu'il soit proche de la sourdine
    -   Rendre le +30 configurable en options de sourdine de 30, 15, 60 secondes

-   Automatiser la capture d'écran

    -   Utilisez UITests pour obtenir des captures d'écran réelles
    -   Utilisez AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w pour obtenir les captures d'écran dans les cadres
    -   Ou quelque chose d'autre
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Tester plus de hacks de clavier
    -   GCKeyboard pour un
    -   FocusEnvironment pour 2
    -   Assurez-vous que la solution utilisée pour iOS ne casse pas la saisie de texte dans les messages / entrées de clavier
    
-   Implémenter iOS 18 AppIntents
    -   Ajouter des intentions d'application de centre de contrôle
        -   Utilisez la bascule pour désactiver/réactiver le son et allumer/éteindre
        -   Utiliser des boutons pour tout le reste
        -   Utiliser une teinture de pourpre correcte
        -   Configurable tout comme les widgets
        -   Faire fonctionner avec une suggestion d'action
    -   Laissez siri / spotlight mieux voir les choses dans mon application d'une manière ou d'une autre?
        -   Ajouter des liens universels aux appareils pour que Siri puisse les lier?
        -   Assurez-vous que la recherche sémantique fonctionne
        -   Implémentez le transfert via ProxyRepresentation et CodableRepresentation pour mon application
-   Fournir une vue minimaliste optionnelle sur iOS qui reproduit de près la vue de la télécommande siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Supportez également les gestes visionos...
    -   Besoin de construire l'API textedit d'abord
-   Ajouter un suivi d'événement sur les actions que les utilisateurs font réellement sur leurs appareils (se connecter à firebase analytics peut-être?)
    -   Suivez qui utilise la vue minimaliste, quelles actions ils font, etc...

## Corrections de bugs

-   Découvrir si la boucle d'appels à `nextPacket` a du sens.
    -   Au lieu de faire une boucle toutes les 10 ms et d'espérer que le timing est correct, devrais-je plutôt faire une boucle sur les paquets reçus et essayer de les programmer à `10ms * globalSequenceNumber + startHostTime` et sampleTime à `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`?
    -   Ensuite, je peux passer d'une boucle `for await` sur l'horloge à une boucle `while !Task.isCancelled` avec un `Task.sleep` dedans.
    -   D'accord, nous devons donc faire une boucle toutes les 10 ms et essayer de tirer le dernier paquet et de le programmer à ce moment-là
    -   Chaque fois que nous effectuons une synchronisation audio
        -   Nous avons lastRenderTime + un paquet de synchronisation
        -   Estimez le nombre de paquets que nous devrions envoyer à + le temps de synchronisation
            -   Temps de rendu + supplémentaire

## Améliorer les tests

-   Tests d'interface utilisateur
    -   Testez lorsque le périphérique est ajouté qu'il apparaît dans le sélecteur de périphérique et est sélectionné par roam
    -   Testez que l'utilisateur peut naviguer vers les paramètres -> devices
    -   Testez que l'utilisateur peut naviguer vers les paramètres -> messages
    -   Testez que l'utilisateur peut naviguer vers les paramètres -> à propos de
    -   Testez que l'utilisateur peut modifier/supprimer des devices
    -   Testez que l'utilisateur peut cliquer sur des boutons une fois les devices ajoutés
    -   Testez que l'utilisateur voit une bannière pour aucun device lorsqu'elle apparaît
    -   Testez que l'utilisateur voit des applinks
    -   Reportez-vous à swiftdat testingmodelcontainer pour les modelcontainers
    -   Reportez-vous ici https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad pour savoir comment configurer les tests

## App Clip

-   AppClip
    -   Ajoutez un bouton "Obtenez un lien partageable pour cet appareil" dans les paramètres -> device
        -   Pré-générez tous les 1,1 M de codes d'AppClip et encodez les emplacements de la sonnerie (0,5 Go)
        -   Faites un bouton pour "Obtenez un lien partageable vers l'appareil!" avec un aperçu d'image du code de l'AppClip (couleur roam)
        -   Téléchargez le code + le lien et convertissez en PNG sur l'appareil lorsqu'un emplacement de l'appareil est changé
        -   Faites en sorte que le code ouvre l'appareil comme un lien partagé vers une image (avec aperçu!)
    -   Rendez également le lien de l'appareil partageable

## Améliorer la messagerie utilisateur autour de la gestion de l'information / du statut

-   Mettre à jour la gestion de l'information / du statut pour mieux gérer l'état volatile
    -   Lors de la déconnexion, la sélection, le clic sur un bouton, le passage au premier plan, l'ouverture de l'application -> Redémarrer la boucle de reconnexion si déconnecté
    -   La boucle de reconnexion consiste à essayer de manière exponentielle de nouvelles connexions défaillantes (0,5 s, double, 10 s d'arrêt)
    -   Lors de la connexion à l'appareil, désactivez toujours les avertissements de réseau
    -   Lors de la tentative de connexion à l'appareil, ou de l'activation de l'appareil, affichez une icône d'information rotative à la place du point gris
    -   Lors de l'activation de l'appareil et de la réussite, afficher une animation lors de la transition du gris -> de la rotation -> du vert
    -   Lors de l'allumage de l'appareil avec WOL et que la connexion ne se fait pas après 5 secondes, ou lors de l'allumage de l'appareil et de l'échec immédiat, affichez un message d'avertissement en dessous de celui du wifi
        -   "Nous n'avons pas pu réveiller votre Roku" (En savoir plus) (Ne plus afficher pour cet appareil), (X)
        -   En savoir plus montre quelques raisons pourquoi
            -   Vous n'êtes pas connecté au même réseau (Affichez le dernier nom de réseau de l'appareil. Demandez à l'utilisateur s'il est connecté à ce réseau)
            -   Votre appareil est en sommeil profond (n'a pas été mis hors tension récemment) et ne peut pas être réveillé
                -   Votre appareil ne prend pas en charge WWOL et est connecté au wifi
                -   Votre appareil ne prend pas en charge WWOL ou WOL
            -   Votre réseau n'est pas configuré de manière à nous permettre d'envoyer des commandes de réveil à l'appareil
    -   Reconnect loop = Tentative exponentielle de reconnexion pour reconnecter ECP
        -   Reconnecter ECP d'abord
        -   Écouter pour informer en second lieu
            -   Gérer +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   Assurez-vous que nous pouvons gérer chacune de ces demandes et leur format...
        -   Rafraîchir l'état de l'appareil en troisième
        -   Rafraîchir l'état de la requête-textedit en quatrième
            -   Mettre à jour l'état du textedit
        -   Rafraîchir les icônes de l'appareil en cinquième
    -   Sur tous les changements après la reconnexion (via notify ou autre)
        -   Mettre à jour l'appareil (stocké) et l'état de l'appareil (volatile)
    -   Après la reconnexion / déconnexion, mettre à jour le statut en ligne dans la vue à distance

## Améliorer la messagerie utilisateur autour des capacités de l'appareil

-   Mettre à jour la messagerie utilisateur lorsque des erreurs peuvent survenir
    -   Lorsque vous cliquez sur un bouton désactivé, ouvrez une fenêtre contextuelle pour montrer pourquoi il est désactivé
        -   Afficher un indicateur d'information sur le bouton pour indiquer que des informations peuvent être reçues lorsqu'il est cliqué?
        -   Mode écouteurs désactivé -> parce que l'appareil ne prend pas en charge le mode écouteurs pour cette application
        -   Contrôle du volume désactivé -> parce que le son est diffusé via HDMI qui ne prend pas en charge les contrôles de volume?
    -   Lors de la numérisation active des appareils et qu'aucun nouveau n'est trouvé, afficher un message d'avertissement sous la liste des appareils
        -   "Nous n'avons pas pu réveiller votre Roku" (Découvrez pourquoi), (X)
        -   En savoir plus affiche une fenêtre contextuelle avec quelques raisons pour lesquelles cela peut se produire
            -   Assurez-vous que votre appareil est allumé et connecté au même réseau wifi que votre application. Si cela ne fonctionne toujours pas, essayez d'ajouter l'appareil manuellement.
            -   Lien https://roam.msd3.io/manually-add-tv.md et https://support.roku.com/article/115001480188 pour plus de dépannage ou de discussion
-   Ajouter une badge pour supportsWakeOnWLAN et supportsMute

## Support ecp textedit

-   Mettre à jour la gestion du clavier pour prendre en charge ecp-textedit sur `KeyboardEntry`
    -   Afficher le clavier lorsque le textedit est ouvert
    -   Masquer le clavier lorsque textedit est fermé
    -   Testez si le collage + la sélection / suppression dans le champ textedit fonctionnent comme prévu
    -   Si ecp-textedit est pris en charge, permettez de sélectionner, de supprimer du texte et de déplacer le curseur. Il suffit de renvoyer le texte chaque fois qu'il change si cela est pris en charge.
    -   Si ecp-textedit n'est pas pris en charge, revenez au comportement actuel d'envoi de clés
    -   Sur macOS, affichez un indicateur lorsque textedit est activé 
    -   Sur macOS, autorisez cmd+v et cmd+c et cmd+x pour copier coller depuis / vers le tampon

Commandes de la session ECP du clavier (notes)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## À mettre à jour lorsque vous abandonnez le support pour iOS 17/macOS 15 (2025)

-   Utilisez les traits de prévisualisation pour injecter des données d'échantillon dans les prévisualisations
    -   Comment faire cela avec iOS 17 toujours un facteur?
    -   Comment utiliser @Previewable dans les prévisualisations avec iOS 17 toujours un facteur??
-   SwiftData
    -   Utiliser le nouveau macro #Index pour les modèles
    -   Utiliser le nouvel macro #Unique pour les modèles
    -   Utiliser la suppression par lot
-   TipKit
    -   Utilisez CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
