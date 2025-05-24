---
hide_table_of_contents: true
---

# Agregar un TV manualmente

1. Encuentra la dirección IP de tu TV
    - Enciende tu TV y navega a **Configuraciones** > **Red** > **Acerca de**
    - La dirección IP debería verse como 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - Es posible que esta página muestre una dirección "Gateway" y una "Dirección IP". Asegúrate de NO usar la dirección "Gateway"
2. Ve a los ajustes de Roam y haz clic en "Agregar un dispositivo manualmente"
3. Nombra tu dispositivo como prefieras e ingresa la IP exactamente como aparece en tu Roku TV
4. Haz clic en Guardar. Ahora tu Roku debería poder conectarse y funcionar normalmente

## ¿Qué pasa si agregas el TV manualmente y Roam aún no puede conectarse o la conexión no funciona correctamente?

Si Roam todavía no puede controlar tu Roku, prueba los siguientes pasos

-   [Solo en WatchOS]: Ve a **Configuración -> Sistema -> Configuraciones avanzadas del sistema -> Control por apps móviles** y asegúrate de que esté en **Permisivo**
-   Asegúrate de que tu dispositivo iOS esté conectado a la misma red WiFi que tu Roku TV
-   Verifica que tu TV esté encendida
-   Asegúrate de que los permisos de Red Local estén habilitados para Roam (o deshabilítalos y vuelve a habilitarlos si ya lo están)
    -   En macOS: Ve a Configuración del Sistema -> Privacidad y seguridad -> Red Local -> Roam
    -   En iOS: Ve a Configuración -> Apps -> Roam -> Red Local
-   Consulta posibilidades adicionales aquí [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## ¿Qué hago si tengo una configuración complicada de red o VPN? ¿Qué protocolos usa esta app?

-   Roam utiliza diferentes protocolos para comunicarse con el TV
    -   TCP (HTTP/Websockets) en el puerto 8060 para enviar comandos al TV y consultar el estado del dispositivo
    -   Paquete mágico WOL (UDP multidifusión a la dirección 255.255.255.255) para encender el TV desde modo de suspensión profunda
    -   RDP (UDP) en el puerto 6970 para la transmisión de audio en modo audífonos
-   Todos los Roku TV utilizan el puerto 8060 y no hay forma de cambiar esto en el TV. Pero si tienes algún tipo de reenvío de puertos y quieres usar un puerto de salida diferente desde Roam, es posible. Solo tienes que ingresar `[IP]:[Puerto]` en el campo "Dirección IP" en lugar de solo `[IP]`. Por ejemplo, ingresa `192.168.8.242:8061` y se usará el puerto `8061`.