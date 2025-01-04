---
hide_table_of_contents: true
---

# Hoja de Ruta de Roam

## Trabajo Completado para la Próxima Actualización

-   Se añadieron widgets de control: Play, Mute, Change Volume y Select desde el Control center!
-   Se mejoró el manejo de los campos de texto para muchas aplicaciones roku
    -   Auto-abrir campo de texto cuando la edición de texto está disponible
    -   Copiar, Cortar, Pegar desde macOS (con teclado)
    -   Copiar, Cortar, Pegar + Edición generalizada en iOS
-   Mejor informe alrededor de los permisos de red local y conectividad
-   Mejora de la funcionalidad del teclado
-   Mejoras en la estabilidad de la conexión

## Próximamente

-   Añadir opciones de presión prolongada a las teclas
    -   Pulsación larga en la flecha derecha para avanzar rápido
    -   Pulsación larga en la flecha izquierda para rebobinar
    -   Pulsación larga en mute para silenciar prolongadamente
        -   Hacer que el +30 sea configurable a 30, 15, 60 opciones de silencio de segundos
        -   Mostrar banner con +30 sec, x para cancelar, indicador de progreso lineal de fondo
            -   Mostrar debajo del panel de botón principal para que esté cerca de mute
        -   Cancela cuando se vuelve a silenciar (y también hace la llamada a la API)
-   Reparar los widgets de macOS

-   Futuro: Proporcionar una vista Minimalista opcional en iOS que replica de cerca la vista del control remoto de Siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Soporte para gestos de visionos también...

## Ideas Futuras Generales

-   Crear un icono personalizado para la barra de menú

-   ¿Cómo hacer texto-a-voz o comandos de voz generales?

    -   Necesito retro-ingeniería del protocolo udp del control remoto por voz de roku
    -   ¿O necesito añadir un texto a voz personalizado con el motor de botón remoto?

-   Automatizar la Captura de Pantallazos

    -   Usa UITests para obtener pantallazos reales para todos los tamaños de dispositivo + localizaciones
    -   Usa AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obtener los pantallazos en los marcos
    -   O algo más
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Probar más trucos de teclado en el iPad

    -   GCKeyboard para uno
    -   FocusEnvironment para dos
    -   Asegurarse de que cualquier solución utilizada para iOS no rompa la entrada de texto en mensajes/entrada de teclado

-   Testeos de Interfaz de Usuario
    -   Testear cuando se añade un dispositivo que se muestra en el selector de dispositivos y es seleccionado por roam
    -   Testear que el usuario puede navegar a configuración -> dispositivos
    -   Testear que el usuario puede navegar a configuración -> mensajes
    -   Testear que el usuario puede navegar a configuración -> acerca de
    -   Testear que el usuario puede editar/borrar dispositivos
    -   Testear que el usuario puede pulsar botones una vez que los dispositivos están añadidos
    -   Testear que el usuario ve la bandera para no dispositivos cuando aparece
    -   Testear que el usuario ve los enlaces de la aplicación
    -   Referirse a swiftdat testingmodelcontainer para modelcontainers
    -   Referirse aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para cómo configurar los tests

## Corrección de Errores

-   Descifra si el ciclo de llamadas a `nextPacket` tiene sentido.
    -   En lugar de hacer un looping cada 10 ms y esperar que el tiempo sea correcto, ¿no debería estar más bien haciendo un looping sobre los paquetes recibidos e intentando programarlos al tiempo de host `10ms * globalSequenceNumber + startHostTime` y sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Entonces puedo cambiar de un bucle `for await` sobre el reloj a un bucle `while !Task.isCancelled` con un `Task.sleep` en él.
    -   Vale, así que necesitamos hacer un looping cada 10 ms e intentar sacar el último paquete y luego programarlo en ese tiempo
    -   Cada vez que hacemos una sincronización de audio
        -   Tenemos lastRenderTime + un paquete de sincronización
        -   Estimar el número de paquete que deberíamos estar enviando en + el tiempo de sincronización
            -   Render Time + adicional

## Mejorar la mensajería al usuario alrededor de la gestión de info/estado/funciones

-   Al encender el dispositivo con WOL y no conectar después de 5 segundos, o al encender el dispositivo y fallar inmediatamente, mostrar un mensaje de advertencia debajo del wifi
    -   "No pudimos despertar tu Roku" (Descubrir más) (No mostrar de nuevo para este dispositivo), (X)
    -   Descubrir más muestra algunas razones por qué
        -   No estás conectado a la misma red (Mostrar el último nombre de red del dispositivo. Preguntar si el usuario está conectado a esta red)
        -   Tu dispositivo está en sueño profundo (no se apagó recientemente) y no puede ser despertado
            -   Tu dispositivo no soporta WWOL y está conectado a wifi
            -   Tu dispositivo no soporta WWOL o WOL
        -   Tu red no está configurada de una forma que nos permita enviar comandos de despertar al dispositivo
-   Al hacer clic en un botón desactivado, mostrar notificación indicando por qué está desactivado
    -   Mostrar un indicador de info en el botón para indicar que se puede recibir información cuando se hace clic en él?
    -   Modo auriculares desactivado -> porque el dispositivo no soporta el modo auriculares para esta aplicación
    -   Control de volumen desactivado -> porque el audio se está reproduciendo por HDMI que no soporta controles de volumen?
-   Al escanear activamente dispositivos y no encontrar nuevos, mostrar un mensaje de advertencia debajo de la lista de dispositivos
    -   "No pudimos despertar tu Roku" (Descubre por qué), (X)
    -   Descubre más muestra una ventana emergente con algunas razones por las que esto puede estar pasando
        -   Asegúrate de que tu dispositivo está encendido y conectado a la misma red wifi que tu aplicación. Si esto todavía no funciona, intenta añadir el dispositivo manualmente.
        -   Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más soluciones de problemas o chat
-   Añadir insignia para supportsWakeOnWLAN y supportsAudioControls

## Para actualizar cuando se deje de dar soporte a iOS 17/macOS 14 (Febrero 2026)

-   Dar una vuelta y eliminar las etiquetas @available(iOS 18)
-   Usar las características de previsualización para inyectar datos de muestra en las previsualizaciones
-   SwiftData
    -   Usar nueva macro #Index para modelos
    -   Usar nueva macro #Unique para modelos
    -   Usar eliminación por lotes
-   TipKit
    -   Usar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698

