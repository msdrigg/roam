---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Acerca de Roam

Roam ofrece todo lo que quieres y nada que no necesitas

-   ¡Funciona en Mac, iPhone, iPad, Apple Watch, Vision Pro o Apple TV!
-   Integración inteligente con la plataforma: atajos de teclado en Mac, usar los botones de volumen del dispositivo para controlar el volumen de la TV en iOS
-   Utiliza atajos y widgets para controlar tu TV sin tener que abrir la app
-   Soporte para modo audífonos (también llamado escucha privada) en Mac, iPad, iPhone, VisionOS y Apple TV (puedes reproducir el audio de la TV a través de tu dispositivo)
-   Descubre dispositivos en tu red local apenas abras la app
-   Diseño intuitivo usando el sistema de diseño nativo SwiftUI de Apple
-   Rápida y liviana, menos de 8 MB en todos los dispositivos y se abre en menos de medio segundo
-   Código abierto (https://github.com/msdrigg/roam)

## Funcionalidades

-   Controles remotos
    -   Roam incluye los controles normales de un control remoto Roku, incluyendo botones direccionales, seleccionar, retroceder, inicio, reproducir/pausar y controles relacionados con la TV cuando el Roku los soporta.
    -   Es posible que los controles de volumen no funcionen en los Roku Stick porque son dispositivos solo HDMI y no pueden controlar el volumen de la TV mediante los comandos de red de Roam para Roku.
-   Entrada de teclado
    -   En macOS, no hay botón de teclado. Cuando la ventana de Roam tiene el foco, el teclado de la Mac funciona automáticamente con la TV.
    -   En iOS y iPadOS, hay un botón de teclado en la parte superior del control remoto.
    -   watchOS no tiene funcionalidad de teclado por ahora.
    -   Algunas apps de Roku ignoran la entrada por teclado de apps remotas. Un ejemplo conocido es Prime Video, donde la entrada de teclado puede no funcionar ya que la app de Roku no la acepta.
-   Modo audífonos/escucha privada
    -   La escucha privada reproduce el audio de la TV a través de tu dispositivo en dispositivos Roku compatibles.
    -   La escucha privada es compatible con Roam en Mac, iPad, iPhone, VisionOS y Apple TV, pero no funciona en todas las Roku TV.

## Problemas Comunes

-   ¿Qué puedo hacer si Roam no detecta automáticamente mi TV?
    -   [Ver aquí](/manually-add-tv)
-   Roam no funciona correctamente en mi Apple Watch
    -   Ve a **Configuración -> Sistema -> Configuración avanzada del sistema -> Control por apps móviles** y asegura que esté establecido en **Permisivo**
-   ¿Por qué no funciona el modo audífonos (escucha privada) en mi TV?
    -   Actualmente el modo audífonos no funciona en algunos modelos de TV. Si el modo audífonos no funciona en Roam, pero sí en la app oficial de Roku, por favor comparte el modelo de tu Roku y cualquier información relevante por correo a [roam-support@msd3.io](mailto:roam-support@msd3.io). Tu reporte me ayudará a saber por dónde buscar para solucionar este error.
-   ¿Qué hago si tengo otro problema o solo quiero dar retroalimentación?
    -   Si es un error o bug, lo mejor es iniciar un envío de retroalimentación desde la aplicación:
        -   Ingresa a la app de Roam y abre la página de configuración
        -   Haz clic en "Enviar retroalimentación". Esto generará un reporte de diagnóstico que puedes compartir con soporte de Roam (roam-support@msd3.io)
        -   Si tu app se está cerrando/crasheando, también asegúrate de tener activada la opción de analíticas en Configuración -> Privacidad y seguridad -> Analíticas y mejoras
            -   Activa "Compartir analíticas de iPhone y Watch" y luego activa "Compartir con desarrolladores de apps" para que Apple me informe si la app se crashea
    -   Si es una solicitud para una nueva función, puedes enviar un email (roam-support@msd3.io), chatear conmigo directamente en la app de Roam (Configuración -> Chatear con el desarrollador) o unirte al [Discord de Roam](https://discord.gg/FqaTNRccbG).
-   ¿Por qué a veces las teclas de flecha no funcionan en iPad?
    -   Esto ocurre porque iPadOS a veces toma el control de las teclas de flecha y las usa para navegar entre botones de la pantalla antes de que podamos detectarlas
    -   Puedes solucionar esto yendo a Configuración -> Accesibilidad -> Teclados y desactivando "Acceso completo al teclado", o alternativamente, ir a Configuración -> Accesibilidad -> Teclados -> Acceso completo al teclado -> Comandos -> Básicos y desactivar los comandos "Mover arriba", "Mover abajo", "Mover a la izquierda" y "Mover a la derecha"
-   ¿Por qué lo que escribo con mi teclado no aparece en la TV?
    -   En algunas apps de Roku, la app ignora la entrada por teclado físico. Puedes comprobar si es un problema de Roam o de la app tratando de usar la función de teclado en la app oficial de Roku y ver si ahí funciona
    -   En macOS, no hay botón de teclado porque el teclado funciona automáticamente con la TV cuando la ventana de Roam está activa. En iOS y iPadOS, usa el botón de teclado en la parte superior del control remoto. watchOS no soporta entrada por teclado por ahora.
    -   Apps con problemas conocidos:
        -   Prime Video
-   ¿Por qué Roam funciona en mi iPhone y Mac pero no en mi Apple Watch?
    -   La app de WatchOS se conecta a la TV por la API ECP de la televisión, que debe estar activada en algunos Roku TV. Para activarla, ve a **Configuración -> Sistema -> Configuración avanzada del sistema -> Control por apps móviles** y asegúrate de que "Acceso de red" esté en "Permisivo"

## Otros recursos

Si tienes preguntas o problemas, puedes contactarme en: [roam-support@msd3.io](mailto:roam-support@msd3.io). También puedes chatear conmigo directamente en la app de Roam (Configuración -> Chatear con el desarrollador) o unirte al [Discord de Roam](https://discord.gg/FqaTNRccbG).

-   [Política de privacidad](/privacy)
-   [Repositorio principal en GitHub](https://github.com/msdrigg/roam)
-   [Discord de Roam](https://discord.gg/FqaTNRccbG)
-   [Descargar en la App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Hoja de ruta](/upcoming-work)
-   [Registro de cambios](/changes)
-   [Dispositivos Roku probados](/tested-tvs)