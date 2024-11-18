---
hide_table_of_contents: true
---

# Hoja de ruta de Roam

## Trabajo terminado para la próxima actualización

- Se agregaron widgets de control: Play, Silencio, Cambiar volumen y Seleccionar desde el centro de control!
- Se mejoró el manejo de los campos de texto para muchas aplicaciones roku 
    - Apertura automática del campo de texto cuando la edición de texto esté disponible
    - Copiar, cortar, pegar desde macOS
    - Copiar, cortar, pegar + Edición generalizada en iOS
- Mejor reporting en torno a los permisos y conectividad de la red local
- Mejoras en la estabilidad de la conexión

## Próximamente

-   En curso
    -   Asegurarse de que la entrada de texto en iOS no se corte bajo el teclado (como está sucediendo ahora)
    -   Arreglar los widgets de macOS
    -   Llevar iOS al lanzamiento en la app store
        - Esperar el seguimiento del recurso
    -   Hacer pruebas más exhaustivas en iOS y macOS para comprobar que el sistema se reconecta y permanece conectado en los siguientes escenarios
        - Después de un largo período de espera
        - Al volver a entrar desde el fondo
        - Al encender el televisor desde el estado APAGADO
        - Al reconectar a internet
        - Al cambiar de dispositivo

-   Siguiente: Agregar temporizador de silencio de +30 segundos con cuenta atrás
    -   Mantener el silencio para silenciar durante +30 segundos
    -   Hacer clic de nuevo para desactivar el silencio y cancelarlo
    -   Mostrar un indicador bajo la línea del botón de silencio 
        -   La barra de progreso tiene un indicador de progreso lineal
        -   La barra de progreso tiene dos botones: +30 segundos, cancelar
        -   Mostrar debajo del panel principal de botones para que esté cerca del silencio
    -   Hacer que el +30 sea configurable a 30, 15, 60 opciones de silencio en segundos

-   Futuro: Proporcionar una vista Minimalista opcional en iOS que replique de cerca la vista del mando a distancia de siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Soporta también los gestos de visionos...

## Ideas generales para el futuro

-   Escribir una entrada de blog sobre el bot de discord y apuntar a mi MessageView
    - Hacer que MessageView sea más autónomo
-   Escribir una entrada de blog sobre la auto-traducción y la lógica en torno a eso
-   Escribir una entrada de blog sobre NWConnection vs URLSession para websockets
-   Escribir una entrada de blog sobre atajos de teclado personalizados
-   Escribir una entrada de blog sobre ECP Textedit API
-   Escribir una entrada de blog sobre los widgets del centro de control

-   Hacer un icono de barra de menús personalizado

-   ¿Cómo hacer voz-a-texto o comandos de voz en general?
    - Necesita retroingeniería del protocolo udp del mando a distancia por voz de roku
    - ¿O necesita añadir texto a voz personalizada con motor de botón remoto?

-   Automatizar la captura de capturas de pantalla

    -   Usar UITests para obtener capturas de pantalla reales para todos los tamaños de dispositivo + localizaciones
    -   Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obtener las capturas de pantalla en los marcos
    -   O algo más
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Probar más trucos de teclado para iPad
    -   GCKeyboard para uno
    -   FocusEnvironment para 2
    -   Asegurarse de que cualquier solución que se utilice en iOS no interrumpe la entrada de texto en los mensajes/entrada de teclado

-   Pruebas UI
    -   Probar cuando se añade un dispositivo que aparece en el selector de dispositivo y es seleccionado por roam
    -   Probar que el usuario puede navegar a ajustes -> dispositivos
    -   Probar que el usuario puede navegar a ajustes -> mensajes
    -   Probar que el usuario puede navegar a ajustes -> acerca de
    -   Probar que el usuario puede editar/borrar dispositivos
    -   Probar que el usuario puede hacer clic en los botones una vez que se añaden los dispositivos
    -   Probar que el usuario ve el banner para no dispositivos cuando aparece
    -   Probar que el usuario ve applinks
    -   Hacer referencia al swiftdat testingmodelcontainer para modelcontainers
    -   Hacer referencia a aquí https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para saber cómo configurar las pruebas

## Correcciones de errores

-   Determinar si el bucle de llamadas a `nextPacket` tiene sentido.
    -   En lugar de hacer el bucle cada 10ms y esperar que el tiempo sea correcto, ¿debería yo estar haciendo el bucle de paquetes recibidos y intentando programarlos en el tiempo del host `10ms * globalSequenceNumber + startHostTime` y el tiempo de muestra a `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Luego puedo cambiar de un bucle `for await` sobre el reloj a un bucle `while !Task.isCancelled` con un `Task.sleep` en él.
    -   Vale, necesitamos hacer un bucle cada 10 ms e intentar sacar el último paquete y luego programarlo a esa hora
    -   Siempre que hacemos una sincronización de audio
        -   Tenemos un último tiempo de renderizado + un paquete de sincronización
        -   Estimar el número de paquete que deberíamos estar enviando en + el tiempo de sincronización
            -   Tiempo de renderizado + adicional

## Mejorar los mensajes al usuario respecto a la gestión de la información/estado/capacidades

-   Al encender el dispositivo con WOL y no conectarse después de 5 segundos, o al encender el dispositivo y fallar inmediatamente, mostrar un mensaje de advertencia debajo del del Wi-Fi.
    -   "No pudimos despertar tu Roku" (Más información) (No mostrar de nuevo para este dispositivo), (X)
    -   Más información muestra algunas razones posibles.
        -   No estás conectado a la misma red (Muestra el último nombre de red del dispositivo. Pregunta si el usuario está conectado a esta red)
        -   Tu dispositivo está en un sueño profundo (no se ha apagado recientemente) y no puede ser despertado
            -   Tu dispositivo no soporta WWOL y está conectado a Wi-Fi
            -   Tu dispositivo no soporta WWOL ni WOL
        -   Tu red no está configurada de una manera que nos permita enviar comandos de despertar al dispositivo
-   Al hacer clic en un botón desactivado, se muestra una notificación indicando por qué está desactivado
    -   ¿Mostrar un indicador de información en el botón para indicar que se puede recibir información cuando se hace clic?
    -   Modo auriculares desactivado -> porque el dispositivo no soporta el modo auriculares para esta aplicación
    -   Control de volumen desactivado -> porque el audio se está reproduciendo por HDMI que no soporta controles de volumen?
-   Al escanear activamente dispositivos y no encontrar nuevos, mostrar un mensaje de advertencia debajo de la lista de dispositivos
    -   "No pudimos despertar tu Roku" (Descubre por qué), (X)
    -   Descubre por qué muestra una ventana emergente con algunas razones por las que esto puede estar sucediendo
        -   Asegúrate de que tu dispositivo esté encendido y conectado a la misma red Wi-Fi que tu aplicación. Si esto sigue sin funcionar, intenta añadir el dispositivo manualmente.
        -   Enlace https://roam.msd3.io/manually-add-tv.md y https://support.roku.com/article/115001480188 para más solución de problemas o para chatear
-   Añadir insignia para supportsWakeOnWLAN y supportsMute

## Para actualizar cuando se deje de soportar iOS 17/macOS 14 (Febrero 2026)

-   Rodear y eliminar las etiquetas @available(iOS 18)
-   Usar traits de vista previa para inyectar datos de muestra en las vistas previas
-   SwiftData
    -   Utilizar el nuevo macro #Index para modelos
    -   Utilizar el nuevo macro #Unique para modelos
    -   Usar la eliminación en batch
-   TipKit
    -   Usar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
