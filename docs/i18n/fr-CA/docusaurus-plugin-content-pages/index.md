---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## À propos de Roam

Roam offre tout ce que vous voulez et rien que vous ne voulez pas

- Fonctionne sur Mac, iPhone, iPad, Apple Watch, Vision Pro ou Apple TV !
- Intégration intelligente de la plateforme avec des raccourcis clavier sur Mac, utilisation des boutons de volume matériel pour contrôler le volume de la TV sur iOS
- Utilisez des raccourcis et des widgets pour contrôler votre télévision sans jamais ouvrir l'application !
- Prise en charge du mode écouteurs (également connu sous le nom d'écoute privée) sur Mac, iPad, iPhone, VisionOS et Apple TV (jouez le son de votre TV à travers votre appareil)
- Découvrir des appareils sur votre réseau local dès que vous ouvrez l'application
- Conception intuitive avec le système de conception SwiftUI natif d'Apple
- Rapide et léger, moins de 8 Mo sur tous les appareils et s'ouvre en moins d'une demi-seconde !
- Open source (https://github.com/msdrigg/roam)

## Problèmes courants

- Que puis-je faire si Roam ne découvre pas automatiquement ma télévision
    - [Voir ici](/manually-add-tv)
- Pourquoi le mode écouteurs (également connu sous le nom d'écoute privée) ne fonctionne-t-il pas sur ma télé?
    - Le mode écouteurs ne fonctionne actuellement pas sur certaines télévisions. Si le mode écouteurs ne fonctionne pas avec Roam, mais fonctionne avec l'application officielle Roku, veuillez partager le nom de modèle de votre Roku et toute autre information pertinente dans un courriel à [roam-support@msd3.io](mailto:roam-support@msd3.io). Votre rapport m'aidera à savoir où chercher pour essayer de corriger ce bug.
- Que faire si j'ai un autre problème ou si je veux simplement donner mon avis ?
    - Si c'est un bug, il sera préférable d'initier un rapport de feedback à partir de l'application
        - Allez dans l'application Roam et ouvrez la page des paramètres
        - Cliquez sur "Envoyer un feedback". Ceci générera un rapport de diagnostic qui peut être partagé avec le support de Roam (roam-support@msd3.io)
        - Si votre application plante, assurez-vous également que vos analyses sont activées dans les paramètres -> Confidentialité & Sécurité -> Analyses & Améliorations
            - Activez "Partager les analyses iPhone & Watch" puis activez "Partager avec les développeurs d'applications" pour qu'Apple me signale lorsqu'une de vos applications plante
    - Si c'est une demande pour une nouvelle fonctionnalité, vous pouvez envoyer un courriel (roam-support@msd3.io), chatter avec moi directement dans l'application Roam (Paramètres -> Chat avec le développeur) ou rejoindre le [Roam Discord](https://discord.gg/FqaTNRccbG).
- Pourquoi les touches fléchées ne fonctionnent-elles parfois pas sur iPad ?
    - Cela est dû au fait que iPadOS prend parfois le contrôle des touches fléchées et les utilise pour naviguer parmi les boutons de l'écran avant que nous puissions les détecter
    - Vous pouvez contourner ce problème en allant dans les paramètres -> Accessibilité -> Claviers et en désactivant "Accès complet au clavier" ou alternativement en allant dans les paramètres -> Accessibilité -> Claviers -> Accès complet au clavier -> Commandes -> Base et en désactivant les commandes "Monter", "Descendre", "Aller à gauche" et "Aller à droite"
- Pourquoi la frappe sur mon clavier n'apparaît-elle pas sur la télévision ?
    - Sur certaines applications Roku, l'application ignore l'entrée du clavier matériel. Vous pouvez vérifier si c'est un bug de Roam ou un bug de l'application en essayant d'utiliser la fonction d'entrée du clavier dans l'application officielle Roku et en vérifiant si cela fonctionne
    - Applications avec bugs connus
        - Prime Video
- Pourquoi Roam fonctionne sur mon iPhone et mon application mac mais pas sur ma Apple Watch ?
    - L'application WatchOS se connecte à la télévision via l'API ECP de la télévision, qui doit être activée sur certaines télévisions Roku. Pour l'activer, allez dans **Paramètres -> Système -> Paramètres avancés du système -> Contrôle par les applications mobiles** et assurez-vous que "Accès au réseau" est réglé sur "Permissif"

## Autres ressources

Si vous avez des questions ou des problèmes, veuillez me contacter à : [roam-support@msd3.io](mailto:roam-support@msd3.io). Vous pouvez également discuter avec moi directement dans l'application Roam (Paramètres -> Discuter avec le développeur) ou rejoindre le [Roam Discord](https://discord.gg/FqaTNRccbG).

- [Politique de confidentialité](/privacy)
- [Répertoire principal sur GitHub](https://github.com/msdrigg/roam)
- [Roam Discord](https://discord.gg/FqaTNRccbG)
- [Télécharger sur l'App Store](https://apps.apple.com/us/app/roam/6469834197)
- [Roadmap](/upcoming-work)
- [Changelog](/changes)
- [Périphériques Roku testés](/tested-tvs)
