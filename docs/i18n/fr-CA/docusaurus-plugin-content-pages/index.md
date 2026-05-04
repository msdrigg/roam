---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## À propos de Roam

Roam offre tout ce que vous voulez, sans le superflu.

-   Fonctionne sur Mac, iPhone, iPad, Apple Watch, Vision Pro ou Apple TV !
-   Intégration intelligente avec raccourcis clavier sur Mac, boutons de volume matériel pour contrôler le volume TV sur iOS
-   Utilisez des raccourcis et widgets pour contrôler votre téléviseur sans jamais ouvrir l’application !
-   Prise en charge du mode écouteurs (aussi appelé écoute privée) sur Mac, iPad, iPhone, VisionOS et Apple TV (écoutez l'audio de votre TV sur votre appareil)
-   Découverte automatique des appareils sur votre réseau local dès l'ouverture de l’application
-   Interface intuitive utilisant le système de design SwiftUI natif d’Apple
-   Rapide et léger : moins de 8 MB sur tous les appareils et s’ouvre en moins d’une demi-seconde !
-   Open source (https://github.com/msdrigg/roam)

## Fonctionnalités

-   Télécommande
    -   Roam inclut tous les contrôles classiques d’une télécommande Roku : touches directionnelles, sélection, retour, accueil, lecture/pause, et commandes TV en fonction des capacités du Roku utilisé.
    -   Les boutons de volume pourraient ne pas fonctionner sur les Roku Sticks parce qu'ils fonctionnent uniquement en HDMI et ne permettent pas de contrôler le volume TV via les commandes réseau Roku de Roam.
-   Saisie au clavier
    -   Sur macOS, il n'y a pas de bouton clavier. Lorsque la fenêtre de Roam est active, le clavier du Mac fonctionne automatiquement avec la TV.
    -   Sur iOS et iPadOS, il y a un bouton clavier en haut de la télécommande.
    -   watchOS ne dispose pas de fonctionnalité clavier pour l’instant.
    -   Certaines applications Roku ignorent la saisie clavier depuis des applications de télécommande. Prime Video, par exemple, refuse la saisie clavier car l’app Roku ne l’accepte pas.
-   Mode écouteurs/écoute privée
    -   L’écoute privée permet d’écouter l’audio du téléviseur sur votre appareil, avec les modèles Roku compatibles.
    -   Ce mode est pris en charge sur Roam pour Mac, iPad, iPhone, VisionOS et Apple TV, mais n’est pas disponible sur tous les modèles de téléviseurs Roku.

## Problèmes courants

-   Que faire si Roam ne trouve pas automatiquement ma TV ?
    -   [Voir ici](/manually-add-tv)
-   Roam ne fonctionne pas correctement sur ma Apple Watch
    -   Allez dans **Réglages -> Système -> Paramètres système avancés -> Contrôle par applications mobiles** et assurez-vous que c’est réglé sur **Permissif**
-   Pourquoi le mode écouteurs (ou écoute privée) ne fonctionne-t-il pas sur ma TV ?
    -   Ce mode ne fonctionne actuellement pas sur certains téléviseurs. Si l’écoute privée ne fonctionne pas avec Roam, mais fonctionne avec l’application officielle Roku, merci de transmettre le nom de modèle de votre Roku et toute information pertinente par courriel à [roam-support@msd3.io](mailto:roam-support@msd3.io). Cela m’aidera à cerner le problème pour le corriger.
-   Que faire si j’ai un autre problème ou si je veux donner des commentaires ?
    -   Pour un bogue, il est préférable de lancer un rapport d’erreur directement depuis l’application :
        -   Ouvrez l’application Roam et allez à la page des paramètres
        -   Cliquez sur « Envoyer des commentaires ». Cela va générer un rapport de diagnostic à partager avec le support Roam (roam-support@msd3.io)
        -   Si votre app plante, assurez-vous aussi que les analyses sont activées dans Paramètres -> Confidentialité et sécurité -> Analyses et améliorations
            -   Activez « Partager les analyses iPhone & Watch » puis « Partager avec les développeurs d’apps » afin qu’Apple m’informe si votre app se ferme inopinément
    -   Pour une demande de nouvelle fonctionnalité, vous pouvez envoyer un courriel (roam-support@msd3.io), discuter directement avec moi dans l’app Roam (Réglages -> Discuter avec le développeur) ou joindre le [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Pourquoi les flèches ne fonctionnent-elles pas parfois sur iPad ?
    -   Cela arrive parce que iPadOS prend parfois le contrôle des touches directionnelles pour naviguer dans l’interface avant que l’app Roam ne puisse les détecter
    -   Vous pouvez contourner ceci en allant dans Réglages -> Accessibilité -> Claviers et désactivez « Accès complet au clavier » ou, alternativement, Réglages -> Accessibilité -> Claviers -> Accès complet au clavier -> Commandes -> Basique et désactivez les commandes « Monter », « Descendre », « Aller à gauche » et « Aller à droite »
-   Pourquoi ce que je tape sur mon clavier n’apparaît-il pas sur la TV ?
    -   Dans certaines apps Roku, la saisie clavier matérielle est ignorée. Pour savoir si cela vient de Roam ou de l’app en question, testez la saisie clavier dans l’application Roku officielle pour voir si ça fonctionne.
    -   Sur macOS, il n’y a pas de bouton clavier, puisque le clavier du Mac fonctionne avec la TV quand la fenêtre Roam est active. Sur iOS et iPadOS, utilisez le bouton clavier tout en haut de la télécommande. watchOS ne prend pas la saisie clavier pour le moment.
    -   Applications avec des problèmes connus :
        -   Prime Video
-   Pourquoi Roam fonctionne sur mon iPhone et mon Mac mais pas sur mon Apple Watch ?
    -   L’application WatchOS se connecte à la TV via l’API ECP de la TV, qui doit parfois être activée sur certains téléviseurs Roku. Pour l’activer, allez dans **Réglages -> Système -> Paramètres système avancés -> Contrôle par applications mobiles** et vérifiez que « Accès réseau » est réglé à « Permissif »

## Autres ressources

Si vous avez des questions ou des problèmes, contactez-moi à : [roam-support@msd3.io](mailto:roam-support@msd3.io). Vous pouvez aussi discuter avec moi directement dans l’app Roam (Réglages -> Discuter avec le développeur) ou rejoindre le [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Politique de confidentialité](/privacy)
-   [Dépôt principal sur GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Télécharger sur l’App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Feuille de route](/upcoming-work)
-   [Journal des modifications](/changes)
-   [Appareils Roku testés](/tested-tvs)