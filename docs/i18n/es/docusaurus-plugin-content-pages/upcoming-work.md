---
hide_table_of_contents: true
---

# Trabajo reciente en Roam

# Próximas actualizaciones de Roam

## Mejoras generales

-   Actualizar las traducciones para asegurar que todas estén al 100%
-   Documentar el bot de soporte de discord y posiblemente duplicarlo en una biblioteca
-   Crear un icono personalizado para la barra de menú

-   ¿Cómo hacer voz-a-texto o comandos de voz generales?
    - Necesita ingeniería inversa del protocolo udp del control remoto de voz de roku
    - O necesita añadir un texto personalizado a voz con motor de botón remoto?

-   Agregar temporizador de silencio de +30 segundos con cuenta regresiva
    -   Mantener silencio para silenciar durante +30 segundos
    -   Clic de nuevo para cancelar el silencio
    -   Mostrar una notificación de barra superior
        -   La barra de progreso tiene un indicador de progreso lineal
        -   La barra de progreso tiene dos botones: +30 segundos, cancelar
        -   Mostrar debajo del panel principal de botones para que esté cerca de silencio
    -   Haz que el +30 sea configurable a 30, 15, 60 opciones de segundo silencio

-   Automatizar la captura de capturas de pantalla

    -   Usar UITests para obtener capturas de pantalla reales
    -   Usar AppScreens para obtener las capturas de pantalla en los marcos
    -   O algo más
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Prueba más trucos de teclado
    -   GCKeyboard para uno
    -   FocusEnvironment para 2
    -   Asegúrate de que cualquier solución que se utilice para iOS no rompa la entrada de texto en mensajes/entrada de teclado
    
-   Implementar iOS 18 AppIntents
    - Añadir intenciones de aplicación del centro de control
        -   Usar toggle para silenciar/desactivar silencio y encender/apagar
        -   Usar botones para todo lo demás
        -   Usar tinte correcto púrpura
        -   Hacer configurable al igual que los widgets
        -   Hacerlo funcionar con la sugerencia de acción
    -   Dejar que siri/spotlight vea mejor las cosas en mi aplicación de alguna manera?
        -   Añadir enlaces universales a los dispositivos para que siri pueda enlazarlos?
        -   Asegurarse de que la búsqueda semántica funciona
        -   Implementar la transferibilidad a través de cadena/codeable para las entidades de mi aplicación
            -   Representación Proxy
            -   Representación Codificable
-   Proporcionar una vista minimalista opcional en iOS que replica de cerca la vista del control remoto de siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Soportar también los gestos de visionos...
    -   Necesidad de construir la api de textedit primero
-   Agregar un seguimiento de eventos sobre qué acciones están haciendo realmente los usuarios en sus dispositivos (¿conectar a firebase analytics quizás?)
    -   Seguir a quién está usando la vista minimalista, qué acciones están haciendo, etc...

## Correcciones de errores

-   Averiguar si el bucle de llamadas a `nextPacket` tiene sentido.
    -   En lugar de hacer un bucle cada 10 ms y esperar que el tiempo sea correcto, ¿debería hacer un bucle sobre los paquetes recibidos e intentar programarlos en el tiempo del host `10ms * globalSequenceNumber + startHostTime` y sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Entonces puedo cambiar de un bucle `for await` sobre el reloj a un bucle `while !Task.isCancelled` con un `Task.sleep` en él.
    -   Entonces necesitamos hacer un bucle cada 10 ms e intentar sacar el último paquete y luego programarlo en ese momento
    -   Siempre que hagamos una sincronización de audio
        -   Tenemos lastRenderTime + un paquete de sincronización
        -   Estimar el número de paquete que deberíamos enviar al + el tiempo de sincronización
            -   Tiempo de renderizado + adicional

## Mejora de las pruebas

-   Pruebas de UI
    -   Probar cuando se añade un dispositivo que aparece en el seleccionador de dispositivo y es seleccionado por roam
    -   Probar que el usuario puede navegar a ajustes -> dispositivos
    -   Probar que el usuario puede navegar a ajustes -> mensajes
    -   Probar que el usuario puede navegar a ajustes -> acerca de
    -   Probar que el usuario puede editar/borrar dispositivos
    -   Probar que el usuario puede hacer clic en los botones una vez que se han añadido los dispositivos
    -   Probar que el usuario ve el banner de no dispositivos cuando aparece
    -   Probar que el usuario ve los enlaces de la aplicación
    -   Consultar el contenedor de pruebas de modelo de swiftdat para los contenedores de modelo
    -   Consultar aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para saber cómo configurar las pruebas

## App Clip

-   AppClip
    -   Añadir un botón "getAShareableLinkToThisDevice" en configuración -> dispositivo
        -   Pre-generar todos los códigos de la app clip 1.1M y codificar las ubicaciones del anillo (0.5GB)
        -   Crear un botón para "Conseguir un enlace compartible al dispositivo!" con una vista previa de imagen al código de la App clip (color roam)
        -   Descargar el código + enlace y convertir en PNG en dispositivo cuando una ubicación del dispositivo es cambiada
        -   Que el código abra el dispositivo como un enlace compartido a una imagen (¡con vista previa!)
    -   También hacer que el enlace real del dispositivo sea compartible

## Mejorar la mensajería al usuario en torno a la gestión de la información/el estado

-   Actualizar la gestión de la información/el estado para manejar mejor el estado volátil
    -   Al desconectar, seleccionar, hacer clic en el botón, pasar al primer plano, abrir la aplicación -> Reiniciar el bucle de reconexión si está desconectado
    -   El bucle de reconexión es para retroceder exponencialmente intentando reconexiones de fallas (0.5s, doble, 10s de retroceso)
    -   Cuando está conectado al dispositivo, siempre desactive las advertencias de red
    -   Cuando intenta conectarse al dispositivo, o intenta encender el dispositivo, muestre un icono de información giratorio en lugar de un punto gris
    -   Al encender el dispositivo y tener éxito, muestre una animación en la transición de gris -> giratorio -> verde
    -   Al encender el dispositivo con WOL y no conectarse después de 5 segundos, o al encender el dispositivo y fallar inmediatamente, muestre un mensaje de advertencia debajo del wifi uno
        -   “No pudimos despertar tu Roku” (Descubre más) (No mostrar de nuevo para este dispositivo), (X)
        -   Más información muestra algunas razones por las que
            -   No estás conectado a la misma red (Mostrar el último nombre de red del dispositivo. Pregunta si el usuario está conectado a esta red)
            -   Tu dispositivo está en sueño profundo (no se apagó recientemente) y no puede ser despertado
                -   Tu dispositivo no soporta WWOL y está conectado a wifi
                -   Tu dispositivo no soporta WWOL o WOL
            -   Tu red no está configurada de una manera que nos permita enviar comandos de despertar al dispositivo
    -   Bucle de reconexión = retroceso Exponencial intento de reconexión a reconectar ECP
        -   Reconectar ECP primero
        -   Escuchar a notificar segundo
            -   Manejar +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   Asegurarse de que podemos manejar cada una de estas
        -   Actualizar estado del dispositivo tercero
        -   Refrescar consulta-textedit-state cuarto
            -   Actualizar estado de textedit
        -   Actualizar los iconos de los dispositivos como quinto
    -   En todos los cambios después de volver a conectar (a través de notificar o cualquier cosa)
        -   Actualizar dispositivo (almacenado) y estado del dispositivo (volátil)
    - Después de volver a conectar/desconectar, actualizar el estado en línea en la vista remota

## Mejora de la mensajería al usuario en torno a las capacidades del dispositivo

-   Actualizar la mensajería al usuario cuando pueden ocurrir errores
    -   Al hacer clic en un botón deshabilitado, abrir el popover para mostrar por qué está deshabilitado
        -   Muestra un indicador de información en el botón para indicar que se puede recibir información cuando se hace clic en él
        -   Modo de auriculares deshabilitado -> porque el dispositivo no soporta el modo de auriculares para esta aplicación
        -   Control de volumen deshabilitado -> porque el audio se está proyectando a través de HDMI que no soporta controles de volumen
    -   Al escanear activamente dispositivos y no encontrar ningún nuevo, mostrar un mensaje de advertencia debajo de la lista de dispositivos
        -   “No pudimos despertar tu Roku” (Descubre por qué), (X)
        -   Saber más muestra un popup con algunas razones por las que esto puede estar sucediendo
            -   Asegúrate de que tu dispositivo esté encendido y conectado a la misma red wifi que tu aplicación. Si esto todavía no funciona, intenta añadir el dispositivo manualmente.
            -   Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más soluciones de problemas o chat
-   Añadir insignia para supportsWakeOnWLAN y supportsMute

## Soporte ecp textedit

-   Actualizar el manejo del teclado para soportar ecp-textedit en `KeyboardEntry`
    -   Mostrar teclado cuando textedit está abierto
    -   Ocultar teclado cuando textedit está cerrado
    -   Probar que pegar + seleccionar/borrar en el campo textedit funciona como se espera
    -   Si se soporta ecp-textedit, permite seleccionar, borrar texto y mover el cursor. Simplemente reenvía el texto cada vez que cambia si se soporta esto.
    -   Si no se soporta ecp-textedit, volver a la conducta actual de enviar claves
    -   En macOS mostrar un indicador cuando textedit está habilitado 
    - En macOS permitir cmd+v y cmd+c y cmd+x para copiar y pegar desde/hacia el buffer

Comandos de sesión ECP de teclado (notas)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Para actualizar al dejar de soportar iOS 17/macOS 15 (2025)

-   Usar características de vista previa para inyectar datos de muestra en las vistas previas
    -   ¿Cómo hacer esto con iOS 17 todavía siendo un factor?
    -   ¿Cómo usar @Previewable en vistas previas con iOS 17 todavía siendo un factor?
-   SwiftData
    -   Usar nueva macro #Index para modelos
    -   Usar nueva macro #Unique para modelos
    -   Usar eliminación en lote
-   TipKit
    -   Usar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698

``