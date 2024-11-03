---
hide_table_of_contents: true
---

# Travail le plus récent sur roam

# Prochaines mises à jour de Roam

- Ajout de widgets de contrôle : Lire, Couper le son, Changer le volume et Sélectionner depuis le centre de contrôle !

## Feuille de route

- Mettre à jour la gestion du clavier pour prendre en charge ecp-textedit sur `KeyboardEntry`
    - Afficher le clavier lorsque textedit est ouvert
    - Masquer le clavier lorsque textedit est fermé
    - S'assurer que le collage + sélection/suppression dans le champ textedit fonctionne comme prévu
    - Utiliser le champ de texte modifié actuel si ecp-textedit n'est pas pris en charge, utiliser le champ de texte standard s'il l'est
    - Sur macOS, prendre en charge le collage avec cmdP, copier/couper avec cmdX + cmdC
    - Si ecp-textedit n'est pas pris en charge, revenir au comportement actuel d'envoi de touches
    - Sur macOS, afficher un champ de texte en bas de l'écran lorsque textedit est activé 
    - Sur macOS, permettre à cmd+v et cmd+c et cmd+x de copier coller à partir de/vers le tampon

- Ajouter un temporisateur de sourdine de +30 secondes avec compte à rebours
    - Maintenez enfoncé la touche muet pour passer en mode muet pendant +30 secondes
    - Cliquer à nouveau pour désactiver le son et l'annuler
    - Afficher un indicateur sous la ligne du bouton muet 
        - La barre de progression a un indicateur de progression linéaire
        - La barre de progression a deux boutons : +30 secondes, annuler
        - Afficher en dessous du panneau principal du bouton pour qu'il soit proche du bouton muet
    - Rendre le +30 configurable à 30, 15, 60 secondes d'options de sourdine

- Fournir une vue Minimaliste en option sur iOS qui reproduit de près la vue de la télécommande Siri
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Prendre en charge les gestes visionos également...

## Idées générales pour le futur

- Rédiger un blog post sur le bot discord et pointer vers mon MessageView
- Rédiger un blog post sur l'auto-traduction et la logique autour de cela

- Faire une icône de barre de menu personnalisée

- Comment faire de la voix-à-texte ou des commandes vocales générales ?
    - Besoin de rétroconcevoir le protocole udp de la télécommande vocale roku
    - Ou besoin d'ajouter du texte personnalisé-à-la-parole avec le moteur de bouton à distance ?

- Automatiser la capture d'écran

    - Utiliser UITests pour obtenir des captures d'écran réelles
    - Utiliser AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w pour obtenir les captures d'écran dans les cadres
    - Ou autre chose
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/templates/s/iphone/

- Tester plus de hacks de clavier
    - GCKeyboard pour l'un
    - FocusEnvironment pour l'autre
    - S'assurer que la solution utilisée pour iOS ne casse pas l'entrée de texte dans les messages/entrée de clavier

- Ajouter un suivi des événements sur les actions que les utilisateurs font réellement sur leurs appareils (se connecter à firebase analytics peut-être ?)
    - Suivre qui utilise la vue minimaliste, quelles actions ils font, etc...

## Correctifs de bugs

- Comprendre si la boucle d'appels à `nextPacket` est logique.
    - Au lieu de boucler toutes les 10 ms et d'espérer que le timing est correct, devrais-je plutôt boucler sur les paquets reçus et essayer de les planifier à l'heure de l'hôte `10ms * globalSequenceNumber + startHostTime` et sampleTime à `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    - Ensuite, je peux passer d'une boucle `for await` sur l'horloge à une boucle `while !Task.isCancelled` avec un `Task.sleep` dedans.
    - Donc, nous devons boucler toutes les 10 ms et essayer de sortir le dernier paquet puis de le programmer à ce moment
    - Chaque fois que nous faisons une synchronisation audio
        - Nous avons lastRenderTime + un packet de synchronisation
        - Estimer le numéro de paquet que nous devrions être en train d'envoyer + le temps de synchronisation
            - Render Time + additionnel

## Améliorer les tests

- Tests d'interface utilisateur
    - Tester lorsqu'un appareil est ajouté qu'il apparait dans le sélecteur d'appareil et est sélectionné par roam
    - Vérifier que l'utilisateur peut naviguer vers les réglages -> appareils
    - Vérifier que l'utilisateur peut naviguer vers les réglages -> messages
    - Vérifier que l'utilisateur peut naviguer vers les réglages -> à propos
    - Test que l'utilisateur peut modifier/supprimer des appareils
    - Tester que l'utilisateur peut cliquer sur des boutons une fois que les appareils sont ajoutés
    - Tester que l'utilisateur voit une bannière pour aucun appareil quand il se présente
    - Tester que l'utilisateur voit des liens d'application
    - Référer à swiftdat testingmodelcontainer pour les modelcontainers
    - Référer ici https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad pour savoir comment mettre en place les tests

## App Clip

- AppClip
    - Ajouter un bouton "getAShareableLinkToThisDevice" sur les paramètres -> appareil
        - Pré-générer tous les 1.1M codes d'app clip et encoder les emplacements d'anneau (0.5GB)
        - Faire un bouton pour "Obtenez un lien partageable vers l'appareil !" avec une prévisualisation d'image du code d'app clip (couleur roam)
        - Télécharger le code + lien et convertir en PNG sur l'appareil lorsqu'un emplacement d'appareil est modifié
        - Faire que le code ouvre l'appareil comme un lien partagé vers une image (avec prévisualisation !)
    - Faire aussi que le lien réel de l'appareil soit partageable

## Améliorer la messagerie utilisateur autour de la gestion de l'information/status

- Mettre à jour la gestion de l'information/status pour mieux gérer l'état volatile
    - En cas de déconnexion, de sélection, de clic sur un bouton, de passage au premier plan, d'ouverture de l'application -> Redémarrez la boucle de reconnexion si déconnecté
    - La boucle de reconnexion consiste à redoubler d'efforts pour réessayer les connexions qui échouent (0.5s, double, 10s de recul)
    - Lorsqu'il est connecté à l'appareil, désactiver toujours les avertissements de réseau
    - Lorsqu'il essaie de se connecter à l'appareil, ou essaie de mettre l'appareil sous tension, montrer une icône d'information en rotation à la place du point gris 
    - Lors de la mise sous tension de l'appareil et de la réussite, montrer une animation sur la transition de gris -> rotation -> vert
    - Lors de la mise sous tension de l'appareil avec WOL et de la non-connexion après 5 secondes, ou lors de la mise sous tension de l'appareil et de l'échec immédiat, montrer un message d'avertissement sous le wifi
        - "Nous n'avons pas pu réveiller votre Roku" (En savoir plus) (Ne plus afficher pour cet appareil), (X)
        - En savoir plus montre quelques raisons possibles
            - Vous n'êtes pas connecté au même réseau (Montrer le dernier nom de réseau de l'appareil. Demander à l'utilisateur s'il est connecté à ce réseau)
            - Votre appareil est en veille profonde (n'a pas été éteint récemment) et ne peut pas être réveillé
                - Votre appareil ne supporte pas WWOL et est connecté en wifi
                - Votre appareil ne supporte pas WWOL ou WOL
            - Votre réseau n'est pas configuré de manière à nous permettre d'envoyer des commandes de réveil à l'appareil
    - Boucle de reconnexion = Redoubler d'efforts pour tenter de se reconnecter à reconnect ECP
        - Reconnecter ECP d'abord
        - Écouter les notifications en second
            - Gérer +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            - S'assurer que nous pouvons gérer chacune de ces demandes et leur format…
        - Actualiser l'état de l'appareil en troisième
        - Rafraîchir query-textedit-state en quatrième
            - Mettre à jour l'état de textedit
        - Rafraîchir les icônes de l'appareil en cinquième
    - Sur tous les changements après la reconnexion (via notify ou autre)
        - Mettre à jour l'appareil (stocké) et DeviceState (voilatile)
    - Après la reconnexion/déconnexion, mettre à jour le statut en ligne dans la vue à distance

## Améliorer la messagerie de l'utilisateur autour des capacités de l'appareil

- Mettre à jour la messagerie de l'utilisateur lorsque des erreurs peuvent se produire
    - Lorsqu'on clique sur un bouton désactivé, ouvrir un popover pour montrer pourquoi il est désactivé
        - Afficher un indicateur d'information sur le bouton pour indiquer que des informations peuvent être reçues lorsqu'on clique dessus ?
        - Mode écouteurs désactivé -> parce que l'appareil ne prend pas en charge le mode écouteurs pour cette application
        - Contrôle du volume désactivé -> parce que l'audio est diffusé par HDMI qui ne prend pas en charge les contrôles de volume ?
    - Lorsqu'on scanne activement des appareils et qu'aucun nouveau n'est trouvé, afficher un message d'avertissement sous la liste des appareils
        - "Nous n'avons pas pu réveiller votre Roku" (Découvrez pourquoi), (X)
        - En savoir plus montre une fenêtre contextuelle avec quelques raisons pour lesquelles cela peut se produire
            - Assurez-vous que votre appareil est allumé et connecté au même réseau wifi que votre application. Si cela ne fonctionne toujours pas, essayez d'ajouter l'appareil manuellement.
            - Lien https://roam.msd3.io/manually-add-tv.md et https://support.roku.com/article/115001480188 pour plus de dépannage ou de discussion
- Ajouter un badge pour supportsWakeOnWLAN et supportsMute

## Notes sur ECP textedit

Commandes de session ECP Keyboard (notes)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## À mettre à jour lors du retrait du support pour iOS 17/macOS 14 (février 2026)

- Faire le tour et supprimer les balises @available(iOS 18)
- Utiliser les traits de prévisualisation pour injecter des données d'échantillon dans les prévisualisations
    - Comment faire cela avec iOS 17 étant toujours un facteur ?
    - Comment utiliser @Previewable dans les prévisualisations avec iOS 17 étant toujours un facteur ??
- SwiftData
    - Utiliser le nouveau macro #Index pour les modèles
    - Utiliser le nouveau macro #Unique pour les modèles
    - Utiliser la suppression par lots
- TipKit
    - Utiliser CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
