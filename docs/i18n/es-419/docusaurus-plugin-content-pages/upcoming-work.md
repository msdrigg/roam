---
hide_table_of_contents: true
---

# Trabajo reciente más en Roam

# Próximas actualizaciones de Roam 

- Se agregaron widgets de control: ¡Reproducir, Silenciar, Cambiar volumen y Seleccionar desde el centro de control! 

## Hoja de ruta

- Actualizar el manejo del teclado para soportar ecp-textedit en `KeyboardEntry`
    - Mostrar teclado cuando se abre textedit
    - Ocultar teclado cuando se cierra textedit
    - Asegurarse de que copiar y pegar + seleccionar/borrar en el campo textedit funcione como se espera
    - Usar el campo de texto modificado actual si ecp-textedit no es compatible, usar el campo de texto estándar si lo es
    - En macOS, soportar pegar con cmdP, copiar/cortar con cmdX + cmdC
    - Si ecp-textedit no es compatible, volver al comportamiento actual de enviar claves
    - En macOS mostrar un campo de texto inferior cuando textedit está habilitado
    - En macOS permitir cmd+v y cmd+c y cmd+x para copiar y pegar desde/hacia el búfer

- Agregar temporizador de silencio de +30 segundos con cuenta regresiva
    - Mantener silencio para silenciar durante +30 segundos
    - Hacer clic de nuevo para desactivar el silencio y cancelarlo
    - Mostrar un indicador debajo de la línea del botón de silencio
        - La barra de progreso tiene un indicador de progreso lineal
        - La barra de progreso tiene dos botones: +30 segundos, cancelar
        - Mostrar debajo del panel de botones principales para que esté cerca de silencio
    - Hacer que el +30 sea configurable para las opciones de silencio de 30, 15, 60 segundos

- Proporcionar una vista opcional minimalista en iOS que imite de cerca la vista del control remoto de Siri
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Soportar también los gestos de visionos...

## Ideas generales para el futuro

- Escribir un post en el blog sobre el bot discord y enlazar a mi MessageView
- Escribir un post en el blog sobre la auto-traducción y la logic alrededor de eso

- Crear icono personalizado para la barra de menú

- ¿Cómo hacer voz-a-texto o comandos de voz generales?
    - Necesito aplicar ingeniería inversa al protocolo udp del control remoto de voz de roku
    - ¿O necesito agregar texto-a-voz personalizado con el motor de botones remotos?

- Automatizar la captura de capturas de pantalla

    - Usar UITests para obtener capturas de pantalla reales
    - Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obtener las capturas de pantalla en los marcos
    - ¿O algo más?
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/templates/s/iphone/

- Probar más trucos de teclado
    - GCKeyboard para uno
    - FocusEnvironment para 2
    - Asegurarse de que la solución que se utiliza para iOS no rompa la entrada de texto en mensajes/entrada de teclado

- Añadir seguimiento de eventos sobre lo que los usuarios realmente están haciendo en sus dispositivos (¿conectar a firebase analytics tal vez?)
    - Realizar seguimiento de quién está utilizando la vista minimalista, qué acciones están realizando, etc...

## Correcciones de error

- Determinar si el ciclo de llamadas a `nextPacket` tiene sentido.
    - En lugar de hacer loop cada 10 ms y esperar que el tiempo sea correcto, ¿debería estar bucleando sobre los paquetes recibidos e intentar programarlos en el tiempo de host `10ms * globalSequenceNumber + startHostTime` y sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`?
    - Entonces podría cambiar de un loop `for await` sobre el reloj a un loop `while !Task.isCancelled` con un `Task.sleep` en él. 
    - Vale, así que necesitamos hacer loop cada 10 ms e intentar sacar el último paquete y luego programarlo en ese momento
    - Cada vez que hacemos una sincronización de audio
        - Tenemos lastRenderTime + un paquete de sincronización
        - Estimar el número de paquete que deberíamos estar enviando en + el tiempo de sincronización
            - Render Time + adicional

## Mejora de las pruebas

- Pruebas de UI
    - Probar cuándo se agrega un dispositivo que aparece en el selector de dispositivos y es seleccionado por roam
    - Probar que el usuario puede navegar a configuración -> dispositivos
    - Probar que el usuario puede navegar a configuración -> mensajes
    - Probar que el usuario puede navegar a configuración -> acerca de
    - Probar que el usuario puede editar/borrar dispositivos
    - Probar que el usuario puede hacer clic en los botones una vez que se añaden los dispositivos
    - Probar que el usuario ve la bandera sin dispositivos cuando aparece
    - Probar que el usuario ve aplinks
    - Referirse a swiftdat testingmodelcontainer para los contenedores de modelo
    - Referirse aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para cómo configurar las pruebas

## App Clip

- AppClip
    - Añadir un botón "getAShareableLinkToThisDevice" en configuración -> dispositivo
        - Pre-generar todos los 1.1M códigos de app clip y codificar las ubicaciones del anillo (0.5GB)
        - Hacer un botón para "¡Obtener un enlace compartible para el dispositivo!" con una vista previa de la imagen al código de app clip (color roam)
        - Descargar el código + enlace y convertir a PNG en el dispositivo cuando se cambia la ubicación de un dispositivo
        - Hacer que el código abra el dispositivo como un enlace compartido a una imagen (¡con vista previa!)
    - También hacer que el enlace del dispositivo sea compartible

## Mejorar la mensajería del usuario en torno a la gestión de información/estado

- Actualizar la gestión de información/estado para manejar mejor el estado volátil
    - En desconexión, selección, clic de botón, pasar al primer plano, abrir la aplicación -> Reiniciar el bucle de reconexión si está desconectado
    - El bucle de reconexión es para retirar exponencialmente las conexiones fallidas (0.5s, doble, backoff de 10s)
    - Cuando se está conectado al dispositivo, siempre desactivar las advertencias de red
    - Cuando se intenta conectar al dispositivo, o intentar encender el dispositivo, mostrar el icono de información en rotación en lugar del punto gris
    - Al encender el dispositivo y tener éxito, mostrar una animación en la transición de gris -> rotación -> verde
    - Al encender el dispositivo con WOL y no conectar después de 5 segundos, o al encender el dispositivo y fallar inmediatamente, mostrar un mensaje de advertencia debajo del wifi
        - "No pudimos despertar tu Roku" (Saber más) (No mostrar de nuevo para este dispositivo), (X)
        - Saber más muestra algunas razones por qué
            - No estás conectado a la misma red (Mostrar el último nombre de red del dispositivo. Preguntar si el usuario está conectado a esta red)
            - Tu dispositivo está en hibernación profunda (no fue apagado recientemente) y no puede ser despertado
                - Tu dispositivo no soporta WWOL y está conectado a wifi
                - Tu dispositivo no soporta WWOL o WOL
            - Tu red no está configurada de manera que nos permita enviar comandos de despertar al dispositivo
    - Bucle de reconexión = Backing off Exponentially attempt para reconectar a ECP reconnect
        - Reconectar ECP primero
        - Escuchar a notificar en segundo lugar
            - Handle +power-mode-changed, +textedit-opened, +textedit-changed, +textedit-closed, +device-name-changed
            - Asegurarse de que podemos manejar cada una de estas solicitudes y su formato…
        - Refresh device state third
        - Refresh query-textedit-state fourth
            - Update textedit state
        - Refresh device icons fifth
    - On all changes after reconnecting (through notify or anything)
        - Update Device (stored) and DeviceState (voilatile)
    - After reconnecting/disconnecting, update online status in remote view

## Mejorar la mensajería del usuario alrededor de las capacidades del dispositivo

- Actualizar la mensajería del usuario cuando puedan ocurrir errores
    - Cuando se haga clic en un botón deshabilitado, abrir el popover para mostrar por qué está deshabilitado
        - ¿Mostrar un indicador de información en el botón para indicar que la información se puede recibir cuando se hace clic?
        - Modo auriculares desactivado -> porque el dispositivo no soporta el modo auriculares para esta aplicación
        - Control del volumen desactivado -> porque el audio se está transmitiendo por HDMI, que no soporta controles de volumen?
    - Cuando se está escaneando activamente en busca de dispositivos y no se encuentran nuevos, mostrar un mensaje de advertencia debajo de la lista de dispositivos
        - "No pudimos despertar tu Roku" (Descubrir por qué), (X)
        - Descubrir más muestra una ventanita con algunas razones por las que esto puede estar ocurriendo
            - Asegúrate de que tu dispositivo esté encendido y conectado a la misma red wifi que tu aplicación. Si esto aún no funciona, intenta agregar el dispositivo manualmente.
            - Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más solución de problemas o chat
- Añadir distintivo para supportsWakeOnWLAN y supportsMute

## Notas de ECP textedit

Comandos de Sesión ECP Keyboard (notas)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## A actualizarse cuando se deje de soportar iOS 17/macOS 14 (Feb 2026)

- Dar la vuelta y quitar las etiquetas @available(iOS 18)
- Usar rasgos de vista previa para inyectar datos de muestra en vistas previas
    - ¿Cómo hacer esto con el iOS 17 todavía siendo un factor?
    - ¿Cómo usar @Previewable en vistas previas con el iOS 17 todavía como un factor??
- SwiftData
    - Utilizar la nueva macro #Index para modelos
    - Utilizar la nueva macro #Unique para modelos
    - Utilizar la eliminación en lotes
- TipKit
    - Utilizar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
