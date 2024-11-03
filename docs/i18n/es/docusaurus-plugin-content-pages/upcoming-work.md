---
hide_table_of_contents: true
---

# Trabajo más reciente en Roam 

# Actualizaciones próximas de Roam

- Se agregaron widgets de control: ¡Reproducir, Silenciar, Cambiar Volumen y Seleccionar desde el Centro de Control!

## Hoja de ruta

- Actualizar el manejo del teclado para dar soporte a ecp-textedit en `KeyboardEntry`
    - Mostrar el teclado cuando se abre textedit
    - Ocultar el teclado cuando se cierra textedit
    - Asegurarse de que el pegado + selección/borrado en el campo textedit funcione como se espera
    - Usar el campo de texto modificado actual si ecp-textedit no es compatible, usar el campo de texto estándar si lo es
    - En macOS, soporte para pegar con cmdP, copiar/cortar con cmdX + cmdC
    - Si ecp-textedit no es compatible, vuelva al comportamiento actual de enviar teclas
    - En macOS, muestra un campo de texto inferior cuando textedit está habilitado
    - En macOS, permite cmd+v y cmd+c y cmd+x para copiar y pegar desde/hacia el búfer

- Agregar temporizador de silencio de +30 segundos con cuenta regresiva
    - Mantén presionado para silenciar durante +30 segundos
    - Haz clic de nuevo para desactivar el silencio y cancelarlo
    - Muestra un indicador debajo de la línea del botón de silencio 
        - La barra de progreso tiene un indicador de progreso lineal
        - La barra de progreso tiene dos botones: +30 segundos, cancelar
        - Muestra debajo del panel de botones principal para estar cerca del botón de silencio
    - Haz que el +30 sea configurable para opciones de silencio de 30, 15, 60 segundos

- Proporcionar una vista minimalista opcional en iOS que replican de cerca la vista del control remoto de siri
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Soportar gestos visionos también...

## Ideas generales para el futuro

- Escribir una publicación de blog sobre el bot de discord y apuntar a mi MessageView
- Escribir una publicación de blog sobre la auto-traducción y la lógica alrededor de eso

- Hacer un icono personalizado para la barra de menú

- ¿Cómo hacer voz-a-texto o comandos de voz generales?
    - Necesito desarmar el protocolo UDP del control remoto de voz de Roku
    - ¿O necesito agregar texto-a-voz personalizado con el motor de botón remoto?

- Automatizar la captura de capturas de pantalla

    - Usar UITests para obtener capturas de pantalla reales
    - Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obtener las capturas de pantalla en los marcos
    - ¿O algo más?
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/templates/s/iphone/

- Realizar más pruebas con los hacks de teclado
    - GCKeyboard para empezar
    - FocusEnvironment para 2
    - Asegúrate de que la solución que se utilice para iOS no rompa la entrada de texto en los mensajes/entrada de teclado

- Añadir un seguimiento de eventos sobre lo que los usuarios están haciendo en sus dispositivos (¿conectar a firebase analytics tal vez?)
    - Rastrear quién está utilizando la vista minimalista, qué acciones están realizando, etc...

## Corrección de errores

- Determinar si el ciclo de llamadas a `nextPacket` tiene sentido.
    - En lugar de hacer un bucle cada 10 ms y esperar que el tiempo sea correcto, ¿debería estar pasando por los paquetes recibidos e intentando programarlos en `10ms * globalSequenceNumber + startHostTime` y sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    - Entonces puedo cambiar de un bucle `for await` sobre el reloj a un bucle `while !Task.isCancelled` con un `Task.sleep` en él.
    - Okey, así que necesitamos hacer un bucle cada 10 ms e intentar sacar el último paquete y luego programarlo en ese momento
    - Cada vez que hacemos una sincronización de audio
        - Tenemos el último tiempo de renderizado + un paquete de sincronización
        - Estimamos el número de paquetes que deberíamos estar enviando en + el tiempo de sincronización
            - Tiempo de renderizado + adicional

## Mejorar las pruebas

- Pruebas de interfaz de usuario
    - Probar cuando se agrega un dispositivo que aparece en el seleccionador de dispositivos y es seleccionado por Roam
    - Probar que el usuario puede navegar a configuración -> dispositivos
    - Probar que el usuario puede navegar a configuración -> mensajes
    - Probar que el usuario puede navegar a configuración -> acerca de
    - Probar que el usuario puede editar/borrar dispositivos
    - Probar que el usuario puede clicar en los botones una vez que se añaden los dispositivos
    - Probar que el usuario ve la bandera para no dispositivos cuando aparece
    - Probar que el usuario ve applinks
    - Consultar el contenedor de pruebas de datamodelcontainer swift para modelcontainers
    - Consultar aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para saber cómo configurar las pruebas

## App Clip

- AppClip
    - Agregar un botón "getAShareableLinkToThisDevice" en configuración -> dispositivo
        - Pre-generar todos los 1.1M códigos de app clip y codificar las ubicaciones del anillo (0.5GB)
        - Hacer un botón para "¡Consigue un enlace compartible al dispositivo!" con una vista previa de la imagen del código de app clip (color roam)
        - Descargar el código + enlace y convertirlo a PNG en el dispositivo cuando se cambia la ubicación de un dispositivo
        - Que el código abra el dispositivo como un enlace compartido a una imagen (¡con vista previa!)
    - También hacer que el enlace del dispositivo sea compartible

## Mejorar los mensajes de usuario acerca de la gestión de información/estado

- Actualizar la gestión de Información/estado para manejar mejor el estado volátil
    - Al desconectarse, seleccionar, hacer clic en el botón, moverse al primer plano, abrir la aplicación -> Reiniciar el bucle de reconexión si se desconecta
    - El bucle de reconexión es para retroceder exponencialmente intentando reintentar conexiones fallidas (0.5s, doble, 10s de retroceso)
    - Al conectarse al dispositivo, siempre desactivar las advertencias de red
    - Al intentar conectarse al dispositivo, o intentar encender el dispositivo, mostrar el icono de información giratorio en lugar de un punto gris
    - Al encender el dispositivo y tener éxito, mostrar una animación al pasar de gris -> giratorio -> verde
    - Al encender el dispositivo con WOL y no conectarse después de 5 segundos, o al encender el dispositivo e inmediatamente fallar, mostrar un mensaje de advertencia debajo del de wifi
        - “No pudimos despertar tu Roku” (Descubre más) (No mostrar más para este dispositivo), (X)
        - Descubre más muestra algunas razones por las que
            - No estás conectado a la misma red (Muestra el último nombre de red del dispositivo. Pregunta si el usuario está conectado a esta red)
            - Tu dispositivo tiene un sueño profundo (no se apagó recientemente) y no puede ser despertado
                - Tu dispositivo no soporta WWOL y está conectado al wifi
                - Tu dispositivo no soporta WWOL o WOL
            - Tu red no está configurada de una manera que nos permita enviar comandos de despertar al dispositivo
    - Bucle de reconexión = Retrocediendo exponencialmente tratar de reconectar a reconectar ECP
        - Reconectar ECP primero
        - Escuchar a notificar segundo
            - Gestionar +cambio modo de alimentación, +apertura de textedit, +cambio de textedit, +cierre de textedit, +cambio del nombre del dispositivo
            - Asegurarse de que podemos manejar cada una de estas solicitudes y su formato…
        - Refrescar el estado del dispositivo tercero
        - Refrescar la consulta-textedit-estado cuarto
            - Actualizar el estado de textedit
        - Refrescar los iconos del dispositivo quinto
    - En todos los cambios después de la reconexión (a través de la notificación o cualquier cosa)
        - Actualizar Dispositivo (almacenado) y Estado del dispositivo (volátil)
    - Después de conectar/desconectar, actualizar el estado en línea en la vista remota

## Mejorar los mensajes de usuario acerca de las capacidades del dispositivo

- Actualizar el envío de mensajes al usuario cuando pueden ocurrir errores
    - Al hacer clic en un botón deshabilitado, abrir un popover para mostrar por qué está deshabilitado
        - Muestra un indicador de información en el botón para indicar que se puede recibir información si se hace clic en él?
        - Modo de auriculares deshabilitado -> porque el dispositivo no admite el modo de auriculares en esta aplicación
        - Control de volumen deshabilitado -> porque el audio se está reproduciendo a través de HDMI que no soporta controles de volumen?
    - Cuando se está buscando activamente dispositivos y no se encuentran nuevos, mostrar un mensaje de advertencia debajo de la lista de dispositivos
        - "No pudimos despertar su Roku" (Descubre por qué), (X)
        - Descubre más muestra un popup con algunas razones por las que esto puede estar ocurriendo
            - Asegúrate de que tu dispositivo está encendido y conectado a la misma red wifi que tu aplicación. Si esto aún no funciona, intenta añadir el dispositivo manualmente.
            - Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más solución de problemas o chat
- Añadir insignia para soportaWakeOnWLAN y soportaMute

## Notas de textedit de ECP

Comandos de sesión de ECP de teclado (notas)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Para actualizar cuando se deje de dar soporte a iOS 17/macOS 14 (Feb 2026)

-   Ir alrededor y remover las etiquetas @available(iOS 18)
-   Usar traits de vista previa para inyectar datos de muestra en las vistas previas
    -   ¿Cómo hacer esto con iOS 17 todavía siendo un factor?
    -   ¿Cómo utilizar @Previewable en las vistas previas con iOS 17 todavía siendo un factor??
-   SwiftData
    -   Usar la nueva macro #Index para los modelos
    -   Usar la nueva macro #Unique para los modelos
    -   Usar la eliminación por lotes
-   TipKit
    -   Usar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
