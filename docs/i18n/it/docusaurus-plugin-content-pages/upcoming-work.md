---
hide_table_of_contents: true
---

# Los trabajos más recientes de Roam

# Próximas actualizaciones de Roam

## Mejoras generales

-   Actualizar las traducciones para asegurarse de que todas están al 100%
-   Documentar el bot de soporte de discord y tal vez duplicarlo en una biblioteca
-   Crear icono de barra de menú personalizado

-   ¿Cómo hacer voz a texto o comandos de voz generales?
    - Necesita realizar ingeniería inversa del protocolo UDP del control remoto de voz Roku
    - ¿O necesita agregar texto a voz personalizado con motor de botón remoto?

-   Agregar temporizador de silencio de +30 segundos con cuenta atrás
    -   Mantenga pulsado para silenciar durante +30 segundos
    -   Haga clic de nuevo para cancelar el silencio
    -   Mostrar una notificación de barra superior
        -   La barra de progreso tiene un indicador de progreso lineal
        -   La barra de progreso tiene dos botones: +30 segundos, cancelar
        -   Mostrar debajo del panel de botones principal para que esté cerca del silencio
    -   Hacer que el +30 sea configurable a opciones de silencio de 30, 15, 60 segundos

-   Automatizar la captura de capturas de pantalla

    -   Use pruebas de IU para obtener capturas de pantalla reales
    -   Use AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obtener las capturas de pantalla en los marcos
    -   U algo más
        -   https://www.figma.com/community/file/886620275115089774 
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Pruebe más trucos de teclado
    -   GCKeyboard para uno
    -   FocusEnvironment para 2
    -   Asegúrese de que la solución que se utilice para iOS no rompa la entrada de texto en los mensajes/entrada de teclado
    
-   Implementar iOS 18 AppIntents
    -   Agregar intenciones de aplicación del centro de control
        -   Use el interruptor para silenciar/desenmudecer y encender/apagar
        -   Use botones para todo lo demás
        -   Use tinte correcto de color púrpura
        -   Hágalo configurable al igual que los widgets
        -   Hacer que funcione con indicación de acción
    -   ¿Permitir que Siri/Spotlight vea mejor las cosas en mi aplicación de alguna manera?
        -   ¿Agregar enlaces universales a los dispositivos para que Siri pueda vincularlos?
        -   Asegurar que la búsqueda semántica funcione
        -   Implementar transferible mediante cadena/codificable para mis entidades de aplicación
            -   Representación del proxy
            -   Representación codificable
-   Proporcionar una vista minimalista opcional en iOS que replique de cerca la vista del mando a distancia de Siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Admite gestos visionos también...
    -   Necesito construir la API textedit primero
-   Agregar algún seguimiento de eventos sobre las acciones que los usuarios realmente están haciendo en sus dispositivos (¿conectar a las analíticas de firebase tal vez?)
    -   Rastrear quién está usando la vista minimalista, qué acciones están haciendo, etc...

## Correcciones de errores

-   Averiguar si el bucle de llamadas a `nextPacket` tiene sentido.
    -   En lugar de hacer un bucle cada 10ms y esperar que el tiempo sea correcto, ¿debería estar recorriendo los paquetes recibidos e intentando programarlos a la hora del host `10ms * globalSequenceNumber + startHostTime` y sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Luego puedo cambiar de un bucle `for await` sobre el reloj a un bucle `while !Task.isCancelled` con un `Task.sleep` en él.
    -   Entonces necesitamos hacer un bucle cada 10 ms e intentar sacar el último paquete y luego programarlo en ese momento
    -   Siempre que hagamos una sincronización de audio
        -   Tenemos lastRenderTime + un paquete de sincronización
        -   Estimamos el número de paquete que deberíamos estar enviando + el tiempo de sincronización
            -   Tiempo de renderizado + adicional

## Mejorar las pruebas

-   Pruebas de IU
    -   Prueba cuando se agrega un dispositivo que aparece en el selector de dispositivos y es seleccionado por roam
    -   Prueba que el usuario puede navegar a configuración -> dispositivos
    -   Prueba que el usuario puede navegar a configuración -> mensajes
    -   Prueba que el usuario puede navegar a configuración -> acerca de
    -   Prueba que el usuario puede editar/borrar dispositivos
    -   Prueba que el usuario puede hacer clic en los botones una vez que los dispositivos se han añadido
    -   Prueba que el usuario ve el banner de no hay dispositivos cuando aparece
    -   Prueba que el usuario ve los enlaces de la aplicación 
    -   Consultar el modelo de pruebas de swiftdat para los contenedores de modelos
    -   Consultar aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para saber cómo configurar las pruebas

## App Clip

-   AppClip
    -   Añade un botón "Obtener un enlace compartible a este dispositivo" en configuración -> dispositivo
        -   Pre-generar todos los 1.1M códigos de App Clip y codificar ubicaciones del anillo (0.5GB)
        -   Crear un botón para "¡Obtener un enlace compartible al dispositivo!" con una vista previa de imagen del código de App Clip (color del roam)
        -   Descargue el código + enlace y convierta a PNG en el dispositivo cuando se cambie la ubicación del dispositivo
        -   Haga que el código abra el dispositivo como un enlace compartido a una imagen (¡con vista previa!)
    -   También hacer que el enlace del dispositivo sea compartible

## Mejorar la mensajería al usuario en relación a la gestión de la información/estado

-   Actualizar la gestión de la información/estado para manejar mejor el estado volátil
    -   En desconexión, selección, clic de botón, movimiento al primer plano, apertura de la aplicación -> Reiniciar el bucle de reconexión si está desconectado
    -   El bucle de reconexión es para intentar de forma exponencial la reconexión de conexiones fallidas (0.5s, doble, 10s de retroceso)
    -   Cuando esté conectado al dispositivo, siempre desactive las advertencias de red
    -   Al intentar conectar al dispositivo, o intentar encender el dispositivo, muestre el icono de información giratorio en lugar del punto gris
    -   Al encender el dispositivo y tener éxito, muestre una animación en la transición de gris -> giratorio -> verde
    -   Al encender el dispositivo con WOL y no conectar después de 5 segundos, o al encender el dispositivo y fallar inmediatamente, mostrar un mensaje de advertencia debajo del wifi
        -   “No pudimos despertar tu Roku” (Descubre más) (No lo vuelvas a mostrar para este dispositivo), (X)
        -   Descubre más muestra algunas razones por las que
            -   No estás conectado a la misma red (muestra el último nombre de red del dispositivo. Pregunta si el usuario está conectado a esta red)
            -   Tu dispositivo está en un sueño profundo (no se apagó recientemente) y no puede ser despertado
                -   Tu dispositivo no soporta WWOL y está conectado a wifi
                -   Tu dispositivo no soporta WWOL o WOL
            -   Tu red no está configurada de una manera que nos permita enviar comandos de despertar al dispositivo
    -   Bucle de reconexión = Exponencialmente intentar reconectar a reconectar ECP
        -   Reconece ECP primero
        -   Escucha notificar segundo
            -   Manejar +cambio-de-modo-de-alimentación,+apertura-de-textedit,+cambio-de-textedit,+cierre-de-textedit,+cambio-de-nombre-del-dispositivo
            -   Asegúrate de que podemos manejar cada una de estas solicitudes y su formato...
        -   Refrescar el estado del dispositivo tercero
        -   Refrescar la consulta-textedit-state cuarto
            -   Actualizar el estado de textedit
        -   Refrescar los iconos del dispositivo quinto
    -   En todos los cambios después de reconectar (a través de notificar o cualquier cosa)
        -   Actualizar el Dispositivo (almacenado) y Estado del Dispositivo (volátil)
    -   Después de reconectar/desconectar, actualizar el estado en línea en la vista remota

## Mejorar la mensajería al usuario en torno a las capacidades del dispositivo

-   Actualizar la mensajería al usuario cuando pueden ocurrir errores
    -   Al hacer clic en un botón desactivado, abrir un menú emergente para mostrar por qué está desactivado
        -   Muestra un indicador de información en el botón para indicar que se puede recibir información cuando se hace clic?
        -   Modo de auriculares desactivado -> porque el dispositivo no soporta el modo de auriculares a esta aplicación
        -   Control de volumen desactivado -> porque el audio se está enviando a través de HDMI que no soporta controles de volumen?
    -   Al escanear activamente los dispositivos y no encontrar nuevos, mostrar un mensaje de advertencia debajo de la lista de dispositivos
        -   “No pudimos despertar tu Roku” (Descubre por qué), (X)
        -   Descubre más muestra un menú emergente con algunas razones por las que esto puede estar ocurriendo
            -   Asegúrate de que tu dispositivo esté encendido y conectado a la misma red wifi que tu aplicación. Si esto todavía no funciona, intenta agregar el dispositivo manualmente.
            -   Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más solución de problemas o chat
-   Añadir insignia para supportsWakeOnWLAN y supportsMute

## Soporte para ecp textedit

-   Actualizar el manejo del teclado para soportar ecp-textedit en `KeyboardEntry`
    -   Mostrar el teclado cuando se abre textedit
    -   Ocultar el teclado cuando se cierra textedit
    -   Testear que pegar + seleccionar/eliminar en el campo textedit funciona como se espera
    -   Si se soporta ecp-textedit, permitir seleccionar, borrar texto y mover el cursor. Simplemente reenvíe el texto cada vez que cambia si esto está soportado.
    -   Si ecp-textedit no está soportado, caer de nuevo al comportamiento actual de enviar teclas
    -   En macOS mostrar un indicador cuando el textedit está habilitado 
    -   En macOS permitir cmd+v y cmd+c y cmd+x para copiar y pegar desde/hacia el buffer

Comandos de sesión de ECP de teclado (notas)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Para actualizar al abandonar el soporte para iOS 17/macOS 15 (2025)

-   Use rasgos de vista previa para inyectar datos de muestra en las vistas previas
    -   ¿Cómo hacer esto con iOS 17 siguiendo siendo un factor?
    -   ¿Cómo usar @Previewable en vistas previas con iOS 17 todavía siendo un factor??
-   SwiftData
    -   Use la nueva macro #Index para modelos
    -   Use la nueva macro #Unique para modelos
    -   Use la eliminación por lotes
-   TipKit
    -   Use CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
