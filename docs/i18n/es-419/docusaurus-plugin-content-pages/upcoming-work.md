---
hide_table_of_contents: true
---

# Hoja de Ruta de Roam

## Trabajo Completado para la Próxima Actualización

- Se añadieron widgets de control: Reproducir, Silenciar, Cambiar Volumen y Seleccionar desde el centro de control!
- Se añadió un mejor manejo del campo de texto para muchas aplicaciones de roku
    - Auto-abrir el campo de texto cuando la edición de texto está disponible
    - Copiar, Cortar, Pegar desde macOS
    - Copiar, Cortar, Pegar + Edición generalizada en iOS
- Mejor reporte de permisos de red local y conectividad
- Mejoramiento de la estabilidad de la conexión

## Próximamente

- En Proceso
    - Asegurarse de que el ingreso de texto en iOS no se recorta bajo el teclado (como está ocurriendo actualmente)
    - Reparar los widgets de macOS
    - Publicar iOS en la tienda de aplicaciones
        - Esperar la respuesta al recurso
    - Realizar mejores pruebas en iOS y macOS para probar que el sistema se vuelve a conectar y se mantiene conectado en los siguientes escenarios
        - Después de esperar mucho tiempo
        - Al regresar desde el fondo
        - Al encender el televisor desde el estado OFF
        - Al volver a conectarse a internet
        - Al cambiar de dispositivos

- Siguiente: añadir un temporizador de silencio de +30 segundos con cuenta regresiva
    - Mantener pulsado para silenciar durante +30 segundos
    - Hacer clic de nuevo para desactivar el silencio y cancelarlo
    - Mostrar un indicador debajo de la línea del botón de silencio
        - La barra de progreso tiene un indicador de progreso lineal
        - La barra de progreso tiene dos botones: +30 segundos, cancelar
        - Mostrar debajo del panel principal de botones para que esté cerca del mute
    - Hacer que el +30 sea configurable para opciones de silencio de 30, 15, 60 segundos


- Futuro: Proveer una vista minimalista opcional en iOS que replica de cerca la vista del control remoto siri
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Soportar también los gestos de visionos...

## Ideas Generales para el Futuro

- Escribir un post de blog sobre el bot de discord y apuntar a mi MessageView
    - Hacer que MessageView sea más autónomo
- Escribir un post de blog sobre la auto-traducción y la lógica alrededor de eso
- Escribir un post de blog sobre NWConnection vs URLSession para websockets
- Escribir un post de blog sobre atajos de teclado personalizados
- Escribir un post de blog sobre ECP Textedit API
- Escribir un post de blog sobre los widgets del centro de control

- Hacer un icono personalizado para la barra de menús

- ¿Cómo hacer la conversión de voz a texto o comandos de voz generales?
    - Necesito hacer ingeniería inversa al protocolo UDP del control remoto de voz de Roku
    - ¿O necesito añadir texto personalizado a voz con el motor de botón remoto?

- Automatizar la Captura de Pantallas

    - Usar UITests para obtener capturas de pantalla reales para todos los tamaños de dispositivos + localizaciones
    - Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obtener las capturas de pantalla en los marcos
    - O algo más
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/templates/s/iphone/

- Intentar más trucos de teclado para iPad
    - GCKeyboard para uno
    - FocusEnvironment para dos
    - Asegurar que cualquier solución utilizada para iOS no rompa la entrada de texto en mensajes/entrada de teclado

- Pruebas de IU
    - Prueba cuando se añade un dispositivo que aparece en el seleccionador de dispositivos y es seleccionado por roam
    - Prueba que el usuario puede navegar a ajustes -> dispositivos
    - Prueba que el usuario puede navegar a ajustes -> mensajes
    - Prueba que el usuario puede navegar a ajustes -> sobre
    - Prueba que el usuario puede editar/borrar dispositivos
    - Prueba que el usuario puede hacer clic en botones una vez que se han añadido dispositivos
    - Prueba que el usuario ve el banner para no dispositivos cuando aparece
    - Prueba que el usuario ve los applinks
    - Referencia a swiftdat testingmodelcontainer para modelcontainers
    - Referencia aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para cómo configurar pruebas

## Corrección de Errores

- Descubrir si el ciclo de llamadas a `nextPacket` tiene sentido.
     - En lugar de hacer loop cada 10ms y esperar que el tiempo sea correcto, ¿debería estar haciendo loop sobre los paquetes recibidos e intentar programarlos al tiempo host `10ms * globalSequenceNumber + startHostTime` y sampleTime a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime` 
     - Entonces puedo cambiar de un ciclo `for await` sobre el reloj a un ciclo `while !Task.isCancelled` con un `Task.sleep` en él.
     - Vale, así que necesitamos hacer loop cada 10 ms e intentar tomar el último paquete y luego programarlo en ese momento
     - Cada vez que hacemos una sincronización de audio
         - Tenemos lastRenderTime + un paquete de sincronización
         - Estimamos el número de paquete que deberíamos estar enviando a + el tiempo de sincronización
             - Tiempo de Renderizado + adicional

## Mejorar la comunicación al usuario alrededor de la gestión de la info/estatus/capacidades

- Cuándo encender el dispositivo con WOL y no conectar después de 5 segundos, o cuándo encender el dispositivo y fallar de inmediato, mostrar un mensaje de advertencia debajo del de wifi
    - "No pudimos despertar tu Roku" (Descubrir más) (No mostrar de nuevo para este dispositivo), (X)
    - Descubrir más muestra algunas razones por las que
        - No estás conectado a la misma red (Mostrar el último nombre de red del dispositivo. Preguntar si el usuario está conectado a esta red)
        - Tu dispositivo está en sueño profundo (no fue apagado recientemente) y no puede ser despertado
            - Tu dispositivo no soporta WWOL y está conectado a wifi
            - Tu dispositivo no soporta WWOL o WOL
        - Tu red no está configurada de forma que nos permita enviar comandos de despertar al dispositivo
- Cuando se hace clic en un botón inhabilitado, se muestra una notificación indicando por qué está inhabilitado
    - ¿Mostrar un indicador de información en el botón para indicar que se puede recibir información cuando se hace clic?
    - El modo auriculares está desactivado -> porque el dispositivo no soporta el modo auriculares para esta app
    - Control de volumen desactivado -> porque el audio se está emitiendo a través de HDMI, que no soporta controles de volumen?
- Cuando se está buscando activamente dispositivos y no se encuentran nuevos, mostrar un mensaje de advertencia debajo de la lista de dispositivos
    - "No pudimos despertar tu Roku" (Descubre por qué), (X)
    - Descubrir más muestra una ventana emergente con algunas razones por las que esto puede estar ocurriendo
        - Asegúrate de que tu dispositivo esté encendido y conectado a la misma red wifi que tu aplicación. Si esto aún no funciona, intenta agregar el dispositivo manualmente.
        - Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más solución de problemas o chat
- Añadir insignia para supportsWakeOnWLAN y supportsMute

## Para actualizar cuando dejemos de soportar iOS 17/macOS 14 (Feb 2026)

- Rodear y remover los tags @available(iOS 18)
- Usar el rasgo de vista previa para inyectar datos de muestra en vistas previas
- SwiftData
    - Usar el nuevo macro #Index para modelos
    - Usar el nuevo macro #Unique para modelos
    - Usar la eliminación por lotes
- TipKit
    - Usar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
