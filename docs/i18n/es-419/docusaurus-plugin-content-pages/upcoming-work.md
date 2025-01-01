---
hide_table_of_contents: true
---

# Hoja de ruta de Roam

## Trabajo completado para la próxima actualización

-   Se agregaron widgets de control: Play, Mute, Cambio de volumen y Selección desde el centro de control!
-   Mejora en el manejo del campo de texto para muchas aplicaciones de Roku
    -   Apertura automática del campo de texto cuando la edición de texto está disponible
    -   Copiar, Cortar, Pegar desde macOS (con teclado)
    -   Copiar, Cortar, Pegar + Modificación generalizada en iOS
-   Mejora en la información sobre los permisos y conectividad de la red local
-   Mejora en la funcionalidad del teclado
-   Se hicieron mejoras en la estabilidad de la conexión

## Próximamente

-   Agregar opciones de pulsación larga a las teclas
    -   Mantener pulsada la flecha hacia la derecha para avanzar rápidamente
    -   Mantener pulsada la flecha hacia la izquierda para retroceder rápidamente
    -   Mantener pulsado el botón de silencio para mutear durante un periodo prolongado
        -   Hacer que los +30 segundos sean configurables a 30, 15, 60 segundos de opciones de silencio
        -   Mostrar un banner con +30 segundos, x para cancelar, indicador de progreso lineal en segundo plano
            -   Mostrar debajo del panel principal de botones para que esté cerca del mute
        -   Cancela cuando se vuelve a mutear (y también hace una llamada a la API)
-   Solucionar los problemas con los widgets de macOS

-   Futuro: Proporcionar una vista Minimalista opcional en iOS que replique de cerca la vista del control remoto de Siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Adicionalmente, soportar los gestos de VisionOS...

## Ideas generales para el futuro

-   Crear un icono de menú personalizado

-   ¿Cómo hacer comandos de voz-a-texto o comandos de voz generales?

    -   Necesidad de ingeniería inversa en el protocolo UDP del control remoto de voz de Roku
    -   ¿O necesidad de añadir texto-a-voz personalizado con el motor de botón remoto?

-   Automatización de la captura de pantalla

    -   Usar UITests para obtener capturas de pantalla reales para todos los tamaños de dispositivo + localizaciones
    -   Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obtener las capturas de pantalla en los marcos
    -   O algo más
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Probar más trucos de teclado en iPad

    -   GCKeyboard como una opción
    -   FocusEnvironment como la segunda opción
    -   Asegurarse que cualquier solución que se utilice para iOS no interrumpa la entrada de texto en los mensajes / entrada de teclado

-   Pruebas de UI
    -   Comprobar cuando se añade un dispositivo que aparece en el selector de dispositivo y es seleccionado por Roam
    -   Comprobar que el usuario puede navegar a los ajustes -> dispositivos
    -   Comprobar que el usuario puede navegar a los ajustes -> mensajes
    -   Comprobar que el usuario puede navegar a ajustes -> acerca de
    -   Comprobar que el usuario puede editar/borrar dispositivos
    -   Comprobar que el usuario puede hacer clic en los botones una vez que se han añadido los dispositivos
    -   Comprobar que el usuario ve el banner de "no hay dispositivos" cuando aparece
    -   Comprobar que el usuario ve los enlaces de las aplicaciones
    -   Consultar el contenedor del modelo de prueba de SwiftData para los contenedores de modelos
    -   Consultar aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para saber cómo configurar las pruebas

## Corrección de errores

-   Determinar si el bucle de llamadas a `nextPacket` tiene sentido.
    -   En lugar de hacer un bucle cada 10 ms y esperar que el tiempo sea correcto, ¿debería estar recorriendo los paquetes recibidos e intentando programarlos en `10ms * globalSequenceNumber + startHostTime` y `sampleTime` a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Luego puedo cambiar de un bucle `for await` sobre el reloj a un bucle `while !Task.isCancelled` con un `Task.sleep` dentro.
    -   Vale, así que necesitamos hacer un bucle cada 10 ms e intentar extraer el último paquete y luego programarlo en ese momento
    -   Cada vez que hacemos una sincronización de audio
        -   Tenemos un lastRenderTime + un paquete de sincronización
        -   Estimamos el número de paquete que deberíamos estar enviando + el tiempo de sincronización
            -   Render Time + additional

## Mejora en la comunicación de información / estado / gestión de capacidades al usuario

-   Al encender el dispositivo con WOL y no conectarse después de 5 segundos, o al encender el dispositivo e inmediatamente fallar, mostrar un mensaje de advertencia debajo del aviso de wifi
    -   “No pudimos despertar tu Roku” (Descubrir más) (No volver a mostrar para este dispositivo), (X)
    -   Descubrir más muestra algunas razones porqué
        -   No estás conectado a la misma red (Mostrar el último nombre de la red del dispositivo. Preguntarle al usuario si está conectado a esta red)
        -   Tu dispositivo está en un sueño profundo (no se apagó recientemente) y no se pudo despertar
            -   Tu dispositivo no admite WWOL y está conectado a wifi
            -   Tu dispositivo no admite WWOL o WOL
        -   Tu red no está configurada de una forma que nos permita enviar comandos de despertar al dispositivo
-   Al hacer clic en un botón deshabilitado, mostrar una notificación indicando por qué está deshabilitado
    -   ¿Mostrar un indicador de información en el botón para indicar que se puede recibir información cuando se hace clic?
    -   Modo de auriculares deshabilitado -> porque el dispositivo no admite el modo de auriculares para esta aplicación
    -   Control de volumen deshabilitado -> ¿porque el audio se está transmitiendo a través de HDMI que no admite controles de volumen?
-   Al escanear activamente para encontrar dispositivos y no encontrar ninguno nuevo, mostrar un mensaje de advertencia debajo de la lista de dispositivos
    -   “No pudimos despertar tu Roku” (Descubrir por qué), (X)
    -   Descubrir más muestra un popup con algunas razones por las cuales esto puede estar ocurriendo
        -   Asegúrate de que tu dispositivo esté encendido y conectado a la misma red wifi que tu aplicación. Si esto aún no funciona, intenta agregar el dispositivo manualmente.
        -   Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más solución de problemas o chat
-   Agregar insignia para supportsWakeOnWLAN y supportsAudioControls

## A actualizar cuando se deje de dar soporte a iOS 17/macOS 14 (Febrero 2026)

-   Ir alrededor y quitar las etiquetas de @available(iOS 18)
-   Usar traits de previsualización para inyectar datos de muestra en las previsualizaciones
-   SwiftData
    -   Usar la nueva macro #Index para los modelos
    -   Usar la nueva macro #Unique para los modelos
    -   Usar la eliminación por lotes
-   TipKit
    -   Usar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
