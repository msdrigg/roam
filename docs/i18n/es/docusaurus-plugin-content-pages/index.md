---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Sobre Roam

Roam te ofrece todo lo que quieres y nada de lo que no necesitas

-   ¡Funciona en Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Integración inteligente con la plataforma: atajos de teclado en Mac, usar los botones físicos de volumen para controlar el volumen del TV en iOS
-   Utiliza atajos y widgets para controlar tu TV ¡sin siquiera abrir la app!
-   Modo auriculares (también llamado escucha privada) disponible en Mac, iPad, iPhone, VisionOS y Apple TV (reproduce el audio del TV a través de tu dispositivo)
-   Descubre los dispositivos en tu red local en cuanto abras la app
-   Diseño intuitivo con el sistema nativo SwiftUI de Apple
-   Rápido y ligero, pesa menos de 8 MB en todos los dispositivos y se abre en menos de medio segundo
-   Código abierto (https://github.com/msdrigg/roam)

## Funcionalidades

-   Controles remotos
    -   Roam incluye los controles remotos estándar de Roku, incluyendo botones direccionales, seleccionar, retroceder, inicio, reproducir/pausa y otros controles relacionados de TV cuando el Roku lo permite.
    -   Los controles de volumen pueden no funcionar en Roku Sticks porque son dispositivos solo HDMI y no pueden controlar el volumen del televisor mediante los comandos de red de Roam para Roku.
-   Entrada de teclado
    -   En macOS, no hay botón de teclado. Cuando la ventana de Roam está en primer plano, el teclado del Mac funciona automáticamente con el TV.
    -   En iOS y iPadOS, hay un botón de teclado en la parte superior del control remoto.
    -   watchOS no tiene función de teclado en este momento.
    -   Algunas aplicaciones Roku no aceptan la entrada de teclado desde apps remotas. Prime Video es un ejemplo conocido con el que la introducción por teclado puede no funcionar porque la app de Roku no la admite.
-   Modo auriculares / escucha privada
    -   La escucha privada reproduce el audio del TV a través de tu dispositivo en los dispositivos Roku compatibles.
    -   El modo de escucha privada es compatible en Roam para Mac, iPad, iPhone, VisionOS y Apple TV, aunque no funciona con todos los televisores Roku.

## Problemas Comunes

-   ¿Qué puedo hacer si Roam no detecta automáticamente mi TV?
    -   [Consulta aquí](/manually-add-tv)
-   Roam no está funcionando correctamente en mi Apple Watch
    -   Por favor dirígete a **Configuración -> Sistema -> Configuración avanzada del sistema -> Control por apps móviles** y asegúrate de que esté en **Permisivo**
-   ¿Por qué el modo auriculares (escucha privada) no funciona en mi TV?
    -   Actualmente el modo auriculares no funciona en algunos televisores. Si el modo no funciona con Roam, pero sí con la app oficial de Roku, por favor comparte el modelo de tu Roku y cualquier información relevante en un correo a [roam-support@msd3.io](mailto:roam-support@msd3.io). Tu informe me ayudará a identificar y corregir este error.
-   ¿Y si tengo otro problema o simplemente quiero dejar comentarios?
    -   Si es un error, lo mejor será que inicies un informe de comentarios desde la aplicación
        -   Abre la app Roam y ve a la página de configuración
        -   Pulsa "Enviar comentarios". Esto generará un informe de diagnóstico que puedes compartir con el soporte de Roam (roam-support@msd3.io)
        -   Si tu app se está cerrando sola, asegúrate también de tener activada la analítica en Configuración -> Privacidad y seguridad -> Analítica y mejoras
            -   Activa "Compartir analítica de iPhone y Watch" y luego "Compartir con desarrolladores", así Apple me notificará cuando tu app se cierre inesperadamente
    -   Si es una solicitud de nueva función, puedes enviar un correo (roam-support@msd3.io), chatear conmigo directamente en la app Roam (Configuración -> Chatear con el desarrollador) o unirte al [Roam Discord](https://discord.gg/FqaTNRccbG).
-   ¿Por qué a veces no funcionan las flechas en el iPad?
    -   Esto sucede porque iPadOS a veces toma el control de las teclas de flecha para navegar entre los botones en pantalla antes de que podamos detectarlas
    -   Puedes solucionarlo yendo a Configuración -> Accesibilidad -> Teclados y desactivar "Acceso total al teclado" o también Configuración -> Accesibilidad -> Teclados -> Acceso total al teclado -> Comandos -> Básicos y desactivar los comandos "Mover arriba", "Mover abajo", "Mover a la izquierda" y "Mover a la derecha"
-   ¿Por qué al escribir en mi teclado no sale en la TV?
    -   En algunas apps de Roku, estas ignoran la entrada de teclado físico. Puedes comprobar si el fallo es de Roam o de la app probando la función de entrada de teclado en la app oficial de Roku y verificando si allí funciona
    -   En macOS, no hay botón de teclado porque el teclado funciona automáticamente con el TV cuando la ventana de Roam está en primer plano. En iOS y iPadOS, usa el botón de teclado que está en la parte superior del control remoto. watchOS no admite el uso de teclado en este momento.
    -   Apps con errores conocidos:
        -   Prime Video
-   ¿Por qué Roam funciona en mi iPhone y Mac pero no en mi Apple Watch?
    -   La app de WatchOS se conecta al TV mediante la API ECP del TV, que debe estar activada en algunos televisores Roku. Para activarla, ve a **Configuración -> Sistema -> Configuración avanzada del sistema -> Control por apps móviles** y asegúrate de que el "Acceso a la red" esté en "Permisivo"

## Otros Recursos

Si tienes dudas o problemas, contáctame en: [roam-support@msd3.io](mailto:roam-support@msd3.io). También puedes chatear conmigo directamente en la app Roam (Configuración -> Chatear con el desarrollador) o unirte a [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Política de Privacidad](/privacy)
-   [Repositorio principal en GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Descargar en la App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Hoja de ruta](/upcoming-work)
-   [Registro de cambios](/changes)
-   [Dispositivos Roku probados](/tested-tvs)
