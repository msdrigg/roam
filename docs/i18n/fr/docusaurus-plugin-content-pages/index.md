---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## À propos de Roam

Roam offre tout ce que vous voulez et rien que vous ne voulez pas

-   Fonctionne sur Mac, iPhone, iPad, Apple Watch, Vision Pro ou Apple TV!
-   Intégration intelligente de la plateforme avec des raccourcis clavier sur Mac, utilisation des boutons de volume matériel pour contrôler le volume de la TV sur iOS
-   Utilisez des raccourcis et des widgets pour contrôler votre TV sans jamais ouvrir l'application!
-   Mode casque (également appelé écoute privée) pris en charge sur Mac, iPad, iPhone, VisionOS et Apple TV (jouez l'audio de votre téléviseur à travers votre appareil)
-   Découvrez les appareils sur votre réseau local dès que vous ouvrez l'application
-   Design intuitif avec le système de conception natif SwiftUI d'Apple
-   Rapide et léger, moins de 8 Mo sur tous les appareils et s'ouvre en moins d'une demi-seconde!
-   Open source (https://github.com/msdrigg/roam)

## Problèmes courants

-   Que puis-je faire si Roam ne découvre pas automatiquement ma TV ?
    -   [Voir ici](/manually-add-tv)
-   Pourquoi le mode casque (alias écoute privée) ne fonctionne-t-il pas sur ma TV ?
    -   Le mode casque ne fonctionne pas actuellement sur certaines TV. Si le mode casque ne fonctionne pas avec Roam, mais fonctionne avec l'application officielle Roku, veuillez partager le nom du modèle de votre Roku et toute autre information pertinente dans un email à [roam-support@msd3.io](mailto:roam-support@msd3.io). Votre rapport m'aidera à savoir où chercher en essayant de corriger ce bug.
-   Que faire si j'ai un autre problème ou si je veux simplement donner un feedback ?
    -   S'il s'agit d'un bug, il sera préférable d'initier un rapport de feedback depuis l'application
        -   Allez dans l'application Roam et ouvrez la page des paramètres
        -   Cliquez sur "Envoyer un feedback". Cela générera un rapport de diagnostic qui peut être partagé avec le support roam (roam-support@msd3.io)
        -   Si votre application plante, assurez-vous également que vos analyses sont activées dans Paramètres -> Confidentialité et Sécurité -> Analyses et Innovations
            -   Activez "Partager les analyses iPhone & Watch" puis activez "Partager avec les développeurs d'applications" pour qu'Apple me rapporte lorsque votre application plante
    -   S'il s'agit d'une demande d'une nouvelle fonctionnalité, vous pouvez envoyer un email (roam-support@msd3.io), me contacter directement dans l'application Roam (Paramètres -> Chat avec le développeur) ou rejoindre le [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Pourquoi les touches fléchées ne fonctionnent-elles parfois pas sur iPad ?
    -   Cela est dû au fait qu'iPadOS prend parfois le contrôle des touches fléchées et les utilise pour naviguer les boutons de l'écran avant que nous puissions les détecter
    -   Vous pouvez contourner ce problème en allant dans Paramètres -> Accessibilité -> Claviers et en désactivant "Accès complet au clavier" ou à la place en allant dans Paramètres -> Accessibilité -> Keyboards -> Full Keyboard Access -> Commands -> Basic et en désactivant les commandes "Move Up", "Move Down", "Move Left" and "Move Right"
-   Pourquoi la frappe sur mon clavier n'apparaît pas à la TV
    -   Sur certaines applications Roku, l'application ignore l'entrée du clavier matériel. Vous pouvez tester si c'est un bug de Roam ou un bug de l'appli en essayant d'utiliser la fonction d'entrée du clavier dans l'application officielle Roku et en vérifiant si cela fonctionne
    -   Applications avec des bugs connus
        -   Prime Video
-   Pourquoi Roam fonctionne sur mon iPhone et mon application Mac mais pas sur ma Apple Watch ?
    -   L'application WatchOS se connecte à la TV via l'API ECP de la TV, qui doit être activée sur certaines TV Roku. Pour l'activer, allez dans **Settings -> System -> Advanced System Settings -> Control by mobile apps** et assurez-vous que "Network Access" est réglé sur "Permissive"

## Autres ressources

Si vous avez des questions ou des problèmes, veuillez me contacter à : [roam-support@msd3.io](mailto:roam-support@msd3.io). Vous pouvez également discuter avec moi directement dans l'application Roam (Settings -> Chat with the Developer) ou rejoindre le [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Politique de confidentialité](/privacy)
-   [Répertoire Core sur GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Télécharger sur l'App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Feuille de route](/upcoming-work)
-   [Journal des modifications](/changes)
-   [Appareils Roku testés](/tested-tvs)