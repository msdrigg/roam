---
hide_table_of_contents: true
---

# Agregar una TV manualmente

1. Encuentra la dirección IP de tu TV
    - Enciende tu TV y navega a **Configuración** > **Red** > **Acerca de**
    - Si no tienes un control remoto físico u otra forma de controlar la TV, revisa la interfaz de administración de tu router doméstico o la lista de clientes DHCP para encontrar la dirección IP del Roku
    - La dirección IP debería verse como 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - En esta página puede aparecer una dirección de "Gateway" y una "Dirección IP". Asegúrate de NO estar usando la dirección de "Gateway"
2. Ve a la configuración de Roam y haz clic en "Agregar un dispositivo manualmente"
3. Nombra tu dispositivo como quieras e ingresa la IP exactamente como aparece en el Roku TV
4. Haz clic en Guardar. Ahora tu Roku debería poder conectarse y funcionar normalmente

## ¿Qué hacer si agregas la TV manualmente y Roam aún no puede conectarse o la conexión no funciona correctamente?

Si Roam todavía no puede controlar tu Roku, prueba los siguientes pasos

-   [Solo WatchOS]: Ve a **Configuración -> Sistema -> Configuración avanzadas del sistema -> Control por aplicaciones móviles** y asegúrate de que esté en **Permisivo**
-   Asegúrate de que tu dispositivo iOS esté conectado a la misma red WiFi que tu Roku TV
-   Asegúrate de que la TV esté encendida
-   Asegúrate de que el permiso de Red Local esté habilitado para Roam (o desactívalo y vuélvelo a activar si ya está habilitado)
    -   En macOS: Ve a Configuración del sistema -> Privacidad y seguridad -> Red local -> Roam
    -   En iOS: Ve a Configuración -> Apps -> Roam -> Red local
-   Si la configuración de tu red doméstica cambió y un dispositivo que funcionaba dejó de funcionar, elimina el dispositivo guardado en Roam y búscalo de nuevo
-   Si el Roku no está conectado a WiFi y no tienes un control remoto físico, sigue los pasos de conexión de la app móvil de Roku aquí: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Consulta posibilidades adicionales aquí [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## ¿Qué pasa si tengo una red/vpn complicada? ¿Qué protocolos utiliza esta app?

-   Roam utiliza varios protocolos diferentes para comunicarse con la TV
    -   TCP (HTTP/Websockets) en el puerto 8060 para enviar comandos a la TV y consultar el estado del dispositivo
    -   Paquete mágico WOL (UDP multicast a la dirección 255.255.255.255) para encender la TV desde un estado de suspensión profunda
    -   RDP (UDP) en el puerto 6970 para el flujo de audio en modo audífonos
-   Todas las Roku TV utilizan el puerto 8060 y no hay manera de cambiar esto desde el lado de la TV. Pero si tienes algún tipo de reenvío de puertos y quieres usar un puerto de salida diferente desde Roam, esto es posible. Solo tienes que ingresar `[IP]:[Puerto]` en el campo "Dirección IP" en vez de solo `[IP]`. Por ejemplo, ingresa `192.168.8.242:8061` y se usará el puerto `8061`.