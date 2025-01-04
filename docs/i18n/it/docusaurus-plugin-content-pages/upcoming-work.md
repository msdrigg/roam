---
hide_table_of_contents: true
---

# Roam Trabajo Planeado

## Trabajo Completado para la Próxima Actualización

-   Se añadieron widgets de control: Reproducir, Silenciar, Cambiar Volumen y Seleccionar desde el centro de control!
-   Se mejoró el manejo del campo de texto para muchas aplicaciones de Roku
    -   Apertura automática del campo de texto cuando la edición de texto está disponible
    -   Copiar, cortar, pegar desde macOS (con el teclado)
    -   Copiar, cortar, pegar + edición generalizada en iOS
-   Mejor reporte alrededor de los permisos de la red local y la conectividad
-   Mejora en la funcionalidad del teclado
-   Mejoras en la estabilidad de la conexión

## Próximamente 

-   Añadir opciones de presionar y mantener a las teclas
    -   Mantén presionada la flecha derecha para avanzar rápido
    -   Mantén presionada la flecha izquierda para retroceder rápido
    -   Mantén presionado el botón de silencio para silenciar durante mucho tiempo
        -   Hacer que los +30 sean configurables a 30, 15, opciones de silencio de 60 segundos
        -   Muestra el banner con +30 seg, x para cancelar, indicador de progreso lineal de fondo
            -   Muestra debajo del panel principal de botones para que esté cerca del botón de silencio
        -   Se cancela al silenciar de nuevo (y también hace una llamada a la API)
-   Solucionar los widgets de macOS

-   Futuro: Proporcionar una vista minimalista opcional en iOS que replica de cerca la vista del mando de Siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Soporte para gestos de visionos también...

## Ideas Generales para el Futuro

-   Hacer un icono de menú personalizado

-   ¿Cómo hacer voz a texto o comandos de voz generales?

    -   Necesito ingeniería inversa del protocolo udp del mando a distancia de voz de Roku
    -   ¿O necesitaría añadir un texto personalizado a voz con el motor de botones del mando a distancia?

-   Automatizar la Captura de Pantallas

    -   Utilizar UITests para obtener capturas de pantalla reales para todos los tamaños de dispositivo + locales
    -   Utilizar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obtener las capturas de pantalla en los marcos
    -   O algo más
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Probar más trucos de teclado en el iPad

    -   Para uno GCKeyboard
    -   Para dos FocusEnvironment
    -   Asegurarse de que cualquier solución que se utilice para iOS no rompa la entrada de texto en los mensajes/entrada de teclado

-   Pruebas de Interfaz de Usuario
    -   Probar cuando se agrega un dispositivo que aparece en el selector de dispositivos y es seleccionado por roam
    -   Probar que el usuario puede navegar a configuración -> dispositivos
    -   Probar que el usuario puede navegar a configuración -> mensajes
    -   Probar que el usuario puede navegar a configuración -> acerca de
    -   Probar que el usuario puede editar/borrar dispositivos
    -   Probar que el usuario puede hacer clic en los botones una vez que se han añadido dispositivos
    -   Probar que el usuario ve la bandera de "no hay dispositivos" cuando aparece
    -   Probar que el usuario ve los enlaces de aplicaciones
    -   Referirse a swiftdat testingmodelcontainer para los modelcontainers
    -   Referirse a aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para saber cómo configurar las pruebas

## Corrección de Errores

-   Averiguar si el bucle de llamadas a `nextPacket` tiene sentido.
    -   En lugar de hacer un bucle cada 10ms y esperar que el tiempo sea correcto, ¿debería estar haciendo un bucle sobre los paquetes recibidos e intentando programarlos a la hora del host `10ms * globalSequenceNumber + startHostTime` y sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Entonces puedo cambiar de un bucle `for await` sobre el reloj a un bucle `while !Task.isCancelled` con un `Task.sleep` en él.
    -   Bueno, entonces necesitamos hacer un bucle cada 10 ms e intentar sacar el último paquete y luego programarlo en ese momento
    -   Cada vez que hacemos una sincronización de audio
        -   Tenemos lastRenderTime + un paquete de sincronización
        -   Estimar el número de paquete que deberíamos estar enviando + el tiempo de sincronización
            -   Render Time + adicional

## Mejorar la comunicación del usuario alrededor de la gestión de información/estado/capacidades

-   Cuando se enciende el dispositivo con WOL y no se conecta después de 5 segundos, o cuando se enciende el dispositivo e inmediatamente falla, mostrar un mensaje de advertencia debajo del wifi
    -   "No pudimos despertar tu Roku" (Descubre más) (No mostrar de nuevo para este dispositivo), (X)
    -   Descubre más muestra algunas razones por las que
        -   No estás conectado a la misma red (Mostrar el último nombre de la red del dispositivo. Pregúntale al usuario si está conectado a esta red)
        -   Tu dispositivo está en sueño profundo (no se ha apagado recientemente) y no se puede despertar
            -   Tu dispositivo no soporta WWOL y está conectado al wifi
            -   Tu dispositivo no soporta WWOL o WOL
        -   Tu red no está configurada para permitirnos enviar comandos de despertar al dispositivo
-   Cuando se hace clic en un botón deshabilitado, se muestra una notificación indicando por qué está deshabilitado
    -   ¿Mostrar un indicador de información en el botón para indicar que se puede recibir información cuando se hace clic en él?
    -   Modo auriculares deshabilitado -> porque el dispositivo no soporta el modo auriculares para esta aplicación
    -   Control de volumen deshabilitado -> ¿porque el audio se está transmitiendo a través de HDMI que no soporta controles de volumen?
-   Cuando se está buscando activamente dispositivos y no se encuentran nuevos, mostrar un mensaje de advertencia debajo de la lista de dispositivos
    -   "No pudimos despertar tu Roku" (Descubre por qué), (X)
    -   Descubre más muestra una ventana emergente con algunas razones por las que esto puede estar ocurriendo
        -   Asegúrate de que tu dispositivo esté encendido y conectado a la misma red wifi que tu aplicación. Si esto aún no funciona, intenta añadir el dispositivo manualmente.
        -   Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más resolución de problemas o chat
-   Añadir distintivo para supportsWakeOnWLAN y supportsAudioControls

## Para actualizar cuando se deje de soportar iOS 17/macOS 14 (Febrero 2026)

-   Ir alrededor y eliminar las etiquetas @available(iOS 18)
-   Uso de rasgos de previsualización para inyectar datos de muestra en las previsualizaciones
-   SwiftData
    -   Usar la nueva macro #Index para modelos
    -   Usar la nueva macro #Unique para modelos
    -   Uso de la eliminación en lote
-   TipKit
    -   Uso de CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
