---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## À propos de Roam

Roam offre tout ce que vous souhaitez et rien de superflu

-   Fonctionne sur Mac, iPhone, iPad, Apple Watch, Vision Pro ou Apple TV !
-   Intégration intelligente avec la plateforme : raccourcis clavier sur Mac, boutons de volume matériel pour contrôler le volume de la TV sur iOS
-   Utilisez des raccourcis et des widgets pour contrôler votre TV sans même ouvrir l’application !
-   Mode écouteurs (écoute privée) pris en charge sur Mac, iPad, iPhone, VisionOS et Apple TV (écoutez l’audio de la TV sur votre appareil)
-   Détection instantanée des appareils sur votre réseau local à l’ouverture de l’application
-   Design intuitif reposant sur le système natif SwiftUI d’Apple
-   Rapide et léger, moins de 8 Mo sur tous les appareils, ouverture en moins d’une demi-seconde !
-   Open source (https://github.com/msdrigg/roam)

## Fonctionnalités

-   Télécommande
    -   Roam inclut toutes les commandes habituelles d’une télécommande Roku, comme les boutons directionnels, sélectionner, retour, accueil, lecture/pause et toutes les commandes TV compatibles avec votre modèle Roku.
    -   Les contrôles de volume peuvent ne pas fonctionner sur les Roku Stick, car ces appareils HDMI ne permettent pas de contrôler le volume TV via les commandes réseau Roku utilisées par Roam.
-   Saisie clavier
    -   Sur macOS, il n’y a pas de bouton clavier. Quand la fenêtre Roam est active, le clavier du Mac fonctionne automatiquement avec la TV.
    -   Sur iOS et iPadOS, un bouton clavier apparaît en haut de la télécommande.
    -   watchOS ne prend pas en charge la fonctionnalité clavier pour le moment.
    -   Certaines applications Roku ignorent l’entrée clavier en provenance d’applications de télécommande. Prime Video, par exemple, ne permet pas l’entrée clavier, car l’application Roku ne la prend pas en charge.
-   Mode écouteurs / écoute privée
    -   L’écoute privée diffuse l’audio de la TV sur votre appareil, sur les modèles Roku compatibles.
    -   L’écoute privée est disponible avec Roam sur Mac, iPad, iPhone, VisionOS et Apple TV, mais elle n’est pas prise en charge sur tous les modèles de TV Roku.

## Problèmes fréquents

-   Que faire si Roam ne détecte pas automatiquement ma TV ?
    -   [Voir ici](/manually-add-tv)
-   Roam ne fonctionne pas correctement sur mon Apple Watch
    -   Veuillez vous rendre dans **Réglages -> Système -> Paramètres système avancés -> Contrôle via les applications mobiles** et vérifiez que l’option est définie sur **Permissif**
-   Pourquoi le mode écouteurs (appelé aussi écoute privée) ne fonctionne-t-il pas sur ma TV ?
    -   Le mode écouteurs ne fonctionne actuellement pas sur certains modèles. Si le mode écouteurs ne fonctionne pas avec Roam mais fonctionne avec l’application officielle Roku, merci de partager le nom du modèle de votre Roku et toute information pertinente par email à [roam-support@msd3.io](mailto:roam-support@msd3.io). Votre signalement m’aidera à cibler le problème pour corriger ce bug.
-   Que faire si j’ai un autre problème ou que je souhaite simplement donner un avis ?
    -   S’il s’agit d’un bug, le plus efficace est de faire remonter un retour depuis l’application
        -   Ouvrez l’application Roam et accédez aux paramètres
        -   Cliquez sur "Envoyer un retour". Ceci générera un rapport de diagnostic que vous pourrez envoyer à l’assistance (roam-support@msd3.io)
        -   Si votre application plante, assurez-vous également que vos analyses sont activées dans Réglages -> Confidentialité et sécurité -> Analyses et améliorations
            -   Activez "Partager les analyses iPhone & Watch" puis "Partager avec les développeurs" pour qu’Apple puisse me signaler les plantages de votre application
    -   Pour suggérer une nouvelle fonctionnalité, vous pouvez envoyer un email (roam-support@msd3.io), discuter directement dans l’application Roam (Paramètres -> Discuter avec le développeur) ou rejoindre le [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Pourquoi les flèches du clavier ne fonctionnent-elles pas parfois sur iPad ?
    -   Ceci est dû au fait qu’iPadOS intercepte parfois les touches fléchées pour naviguer entre les boutons de l’écran avant que Roam puisse les détecter
    -   Vous pouvez contourner ce problème en allant dans Réglages -> Accessibilité -> Claviers et en désactivant “Accès complet au clavier”, ou en passant par Réglages -> Accessibilité -> Claviers -> Accès complet au clavier -> Raccourcis -> Basique puis en désactivant les commandes “Monter”, “Descendre”, “Aller à gauche” et “Aller à droite”
-   Pourquoi ce que j’écris au clavier n’apparaît-il pas sur la TV ?
    -   Certaines applications Roku ignorent l’entrée du clavier matériel. Vous pouvez vérifier s’il s’agit d’un bug de Roam ou de l’application en essayant la saisie clavier dans l’application officielle Roku pour voir si cela fonctionne.
    -   Sur macOS, il n’y a pas de bouton clavier car le clavier Mac fonctionne automatiquement avec la TV quand la fenêtre Roam est active. Sur iOS et iPadOS, utilisez le bouton clavier en haut de la télécommande. watchOS ne prend pas en charge l’entrée clavier pour le moment.
    -   Applications connues avec des bugs
        -   Prime Video
-   Pourquoi Roam fonctionne-t-il sur mon iPhone et mon Mac mais pas sur mon Apple Watch ?
    -   L’application WatchOS se connecte à la TV via l’API ECP de la TV, qui doit être activée sur certaines Roku TV. Pour l’activer, rendez-vous dans **Réglages -> Système -> Paramètres système avancés -> Contrôle via les applications mobiles** et vérifiez que “Accès réseau” est réglé sur “Permissif”

## Autres ressources

Si vous avez des questions ou des soucis, contactez-moi à l’adresse : [roam-support@msd3.io](mailto:roam-support@msd3.io). Vous pouvez aussi discuter directement avec moi dans l’app Roam (Paramètres -> Discuter avec le développeur) ou rejoindre le [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Politique de confidentialité](/privacy)
-   [Dépôt principal sur GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Télécharger sur l’App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Feuille de route](/upcoming-work)
-   [Notes de version](/changes)
-   [Appareils Roku testés](/tested-tvs)