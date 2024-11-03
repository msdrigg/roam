---
hide_table_of_contents: true
---

# Trabajo más reciente en Roam

# Próximas actualizaciones de Roam

## Mejoras generales

-   Actualizar las traducciones para asegurarse de que todas estén al 100%
-   Documentar el bot de soporte de Discord y quizás duplicarlo en una biblioteca
-   Crear un icono personalizado para la barra de menú

-   ¿Cómo hacer voz a texto o comandos de voz generales?
    - Se necesita ingeniería inversa del protocolo UDP del control remoto de voz de Roku
    - ¿O se necesita agregar texto personalizado a voz con motor de botón remoto?

-   Agregar temporizador de silencio de +30 segundos con cuenta regresiva
    -   Mantén presionado el silencio para silenciar durante +30 segundos 
    -   Haz clic de nuevo para cancelar el silencio
    -   Mostrar una notificación en la barra superior
        - La barra de progreso tiene un indicador de progreso lineal
        - La barra de progreso tiene dos botones: +30 segundos, cancelar
        - Mostrar debajo del panel de botones principal, por lo que está cerca del silencio
    -   Hacer que los +30 sean configurables para opciones de silencio de 30, 15 y 60 segundos

-   Automatizar la captura de capturas de pantalla

    -   Usar las pruebas de IU para obtener capturas de pantalla reales
    -   Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obtener las capturas de pantalla en los marcos
    -   O algo más
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Probar más trucos de teclado
    -   GCKeyboard para uno
    -   FocusEnvironment para 2
    -   Asegúrate de que cualquier solución que se utilice para iOS no rompa la entrada de texto en mensajes/entrada de teclado
    
-   Implementar iOS 18 AppIntents
    -   Añadir intenciones de aplicación del centro de control
        - Usar conmutación para silenciar/desactivar silencio y encender/apagar
        - Usar botones para todo lo demás
        - Usar tono morado correcto
        - Hacer configurables igual que los widgets
        - Hacer que funcione con el indicador de acción
    - Sly y Spotlight podrían ver mejor las cosas en mi aplicación ¿de alguna manera?
        - ¿Añadir enlaces universales a los dispositivos para que Sly pueda enlazar a ellos?
        - Asegurarse de que la búsqueda semántica funcione
        - Implementar transferible a través de string/codeable para las entidades de mi aplicación
            - ProxyRepresentation
            - CodableRepresentation
-   Proporcionar una vista minimalista opcional en iOS que replica de cerca la vista del control remoto de Siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   También soportará gestos de visionos...
    -   Primero necesita construir la API de edición de texto
-   Agregar algún seguimiento de eventos sobre qué acciones están realizando realmente los usuarios en sus dispositivos (¿conectar con Firebase Analytics tal vez?)
    -   ¿Quién está utilizando la vista minimalista, qué acciones están realizando, etc.?

## Solución de errores

-   Averiguar si el bucle de llamadas a `nextPacket` tiene sentido.
    -   En lugar de hacer bucle cada 10 ms y esperar que el tiempo sea correcto, ¿debería estar haciendo bucle sobre los paquetes recibidos y tratando de programarlos a la hora del host `10 ms * globalSequenceNumber + startHostTime` y sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Luego puedo cambiar de un bucle `for await` sobre el reloj a un bucle `while !Task.isCancelled` con un `Task.sleep` en él.
    -   Bien, necesitamos hacer un bucle cada 10 ms e intentar extraer el último paquete y luego programarlo en ese tiempo
    -   Cada vez que hacemos una sincronización de audio
        -   Tenemos lastRenderTime + un paquete de sincronización
        -   Estimamos el número de paquete que deberíamos estar enviando + el tiempo de sincronización
            -   Render Time + additional

## Mejorar las pruebas

-   Pruebas de IU
    -   Probar cuando se añade un dispositivo se muestra en el selector de dispositivo y es seleccionado por Roam
    -   Probar que el usuario puede navegar a configuración -> dispositivos
    -   Probar que el usuario puede navegar a configuración -> mensajes
    -   Probar que el usuario puede navegar a configuración -> acerca de
    -   Probar que el usuario puede editar/eliminar dispositivos
    -   Probar que el usuario puede hacer clic en los botones una vez que se agregan los dispositivos
    -   Probar que el usuario ve el banner para no dispositivos cuando aparece
    -   Probar que el usuario ve los enlaces de aplicaciones
    -   Referirse a swiftdat testingmodelcontainer para modelcontainers
    -   Ver aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para cómo configurar las pruebas

## App Clip

-   AppClip
    -   Añadir un botón "Obtener un enlace compartible a este dispositivo" en configuración -> dispositivo
        -   Pre-generar todos los 1.1M códigos de clips de aplicación y codificar las localizaciones de anillos (0.5GB)
        -   Hacer un botón para "¡Obtener un enlace compartible al dispositivo!" con una vista previa de la imagen al código del clip de aplicación (color Roam)
        -   Descargar el código + enlace y convertirlo a PNG en el dispositivo cuando se cambia la ubicación de un dispositivo
        -   Hacer que el código abra el dispositivo como un enlace compartido a una imagen (¡con vista previa!)
    -   Además hacer que el enlace del dispositivo real sea compartible

## Mejorar el manejo de mensajes para el usuario en torno a la gestión de la información/estado

-   Actualizar la gestión de la información/el estado para manejar mejor el estado volátil
    -   Al desconectar, seleccionar, hacer clic en el botón, mover al primer plano, abrir la aplicación -> Reiniciar el bucle de reconexión si está desconectado
    -   El bucle de reconexión es para volver a intentar de forma exponencial las conexiones que fallan (0.5s, doble, 10s de retroceso)
    -   Cuando esté conectado al dispositivo, siempre desactivar las advertencias de red
    -   Cuando se intenta conectar al dispositivo, o cuando se intenta encender el dispositivo, se muestra un icono de información giratorio en lugar de un punto gris.
    -   Al encender el dispositivo y tener éxito, se muestra una animación en la transición de gris -> girando -> verde
    -   Al encender el dispositivo con WOL y no conectar después de 5 segundos, o al encender el dispositivo e inmediatamente fallar, muestra un mensaje de advertencia debajo del wifi
        -   “No pudimos despertar tu Roku” (Obtener más información) (No volver a mostrar para este dispositivo), (X)
        -   Obtener más información muestra algunas razones por las que
            -   No estás conectado a la misma red (Mostrar el último nombre de red del dispositivo. Pregunta si el usuario está conectado a esta red)
            -   Tu dispositivo está en sueño profundo (no fue apagado recientemente) y no puede ser despertado
                -   Tu dispositivo no soporta WWOL y está conectado a wifi
                -   Tu dispositivo no soporta WWOL ni WOL
            -   Tu red no está configurada de una manera que nos permita enviar comandos de despertar al dispositivo
    -   Bucle de reconexión = Retroceso exponencial intentar reconectar a reconectar ECP
        -   Reconectar ECP primero
        -   Escuchar para notificar segundo
            -   Manejar +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   Asegúrate de que podemos manejar cada una de estas solicitudes y su formato…
        -   Refrescar el estado del dispositivo tercero
        -   Refrescar consulta-textedit-estado cuarto
            -   Actualizar el estado de edición de texto
        -   Refrescar los iconos del dispositivo quinto
    -   En todos los cambios después de reconectar (a través de notificar o cualquier otra cosa)
        -   Actualizar Device (almacenado) y DeviceState (volátil)
    -   Después de reconectar/desconectar, actualizar el estado en línea en la vista remota

## Mejorar el manejo de mensajes para el usuario en torno a las capacidades del dispositivo

-   Actualizar el manejo de mensajes cuando pueden ocurrir errores
    -   Cuando se hace clic en un botón deshabilitado, abrir un popover para mostrar por qué está deshabilitado
        -   Mostrar un indicador de información en el botón para indicar que se puede recibir información cuando se hace clic en él?
        -   Modo de auriculares deshabilitado -> porque el dispositivo no soporta el modo de auriculares para esta aplicación
        -   Control de volumen deshabilitado -> porque el audio se está reproduciendo a través de HDMI, que no soporta controles de volumen?
    -   Cuando se está escaneando activamente para encontrar dispositivos y no se encuentran nuevos, se muestra un mensaje de advertencia debajo de la lista de dispositivos
        -   “No pudimos despertar tu Roku” (Descubre por qué), (X)
        -   Descubre más muestra un pop-up con algunas razones por las que esto puede estar ocurriendo
            -   Asegúrate de que tu dispositivo está encendido y conectado a la misma red wifi que tu aplicación. Si esto todavía no funciona, intenta añadir el dispositivo manualmente.
            -   Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más solución de problemas o chat
-   Añadir insignia para supportsWakeOnWLAN y supportsMute

## Soporte ecp textedit

-   Actualizar el manejo del teclado para soportar ecp-textedit en `KeyboardEntry`
    -   Mostrar teclado cuando el textedit se abre
    -   Ocultar teclado cuando el textedit se cierra
    -   Probar que pegar + seleccionar/delete en el campo de textedit funciona según lo esperado
    -   Si se soporta ecp-textedit, permitir seleccionar, borrar texto y mover el cursor. Simplemente vuelve a enviar texto cada vez que cambia si se soporta esto.
    -   Si no se soporta ecp-textedit, retroceder al comportamiento actual de enviar teclas
    -   En macOS se muestra un indicador cuando el textedit está habilitado 
    -   En macOS permite cmd+v y cmd+c y cmd+x para copiar pegar desde/hacia el búfer

Comandos de sesión del teclado ECP (notas)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Para actualizar cuando elimine el soporte para iOS 17/macOS 15 (2025)

-   Usar los rasgos de vista previa para inyectar datos de ejemplo en las vistas previas
    -   ¿Cómo hacer esto con el iOS 17 todavía siendo un factor?
    -   ¿Cómo usar @Previewable en vistas previas con el iOS 17 como un factor??
-   SwiftData
    -   Usar el nuevo #Index macro para modelos
    -   Usar el nuevo #Unique macro para modelos
    -   Usar la eliminación por lotes
-   TipKit
    -   Usar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698