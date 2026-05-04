---
hide_table_of_contents: true
---

# Agregar un TV manualmente

1. Encuentra la dirección IP de tu TV
    - Enciende tu TV y navega a **Configuración** > **Red** > **Acerca de**
    - Si no tienes un control remoto físico o algún otro método para controlar el TV, revisa la interfaz de administración de tu router doméstico o la lista de clientes DHCP para encontrar la dirección IP del Roku
    - La dirección IP debería verse como 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - En esta página puede aparecer una dirección "Gateway" y una "Dirección IP". Asegúrate de NO estar usando la dirección "Gateway"
2. Dirígete a la configuración de Roam y haz clic en "Agregar un dispositivo manualmente"
3. Nombra tu dispositivo como desees e ingresa exactamente la dirección IP que muestra el Roku TV
4. Haz clic en Guardar. Ahora tu Roku debería poder conectarse y funcionar normalmente

## ¿Qué ocurre si agrego el TV manualmente pero Roam aún no puede conectar o la conexión no funciona correctamente?

Si Roam aún no puede controlar tu Roku, por favor intenta los siguientes pasos

-   [Sólo WatchOS]: Ve a **Configuración -> Sistema -> Configuración avanzada del sistema -> Control por aplicaciones móviles** y asegúrate de que esté configurado en **Permisivo**
-   Asegúrate de que tu dispositivo iOS esté conectado a la misma red WiFi que tu Roku TV
-   Asegúrate de que el TV esté encendido
-   Asegúrate de que el permiso de Red local esté habilitado para Roam (o desactívalo y vuelve a activarlo si ya estaba habilitado)
    -   En macOS: Ve a Configuración del sistema -> Privacidad y seguridad -> Red local -> Roam
    -   En iOS: Ve a Configuración -> Apps -> Roam -> Red local
-   Si la configuración de tu red doméstica cambió y un dispositivo que funcionaba dejó de hacerlo, elimina el dispositivo guardado en Roam y vuelve a escanearlo
-   Si el Roku no está conectado a WiFi y no tienes un control remoto físico, sigue los pasos de conexión de la aplicación móvil de Roku aquí: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Consulta más posibilidades aquí [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## ¿Qué pasa si tengo una red o configuración VPN complicada? ¿Qué protocolos utiliza esta app?

-   Roam utiliza varios protocolos diferentes para comunicarse con el TV
    -   TCP (HTTP/Websockets) en el puerto 8060 para enviar comandos al TV y consultar el estado del dispositivo
    -   Paquete mágico WOL (UDP multicast a la dirección 255.255.255.255) para despertar el TV desde un estado de suspensión profunda
    -   RDP (UDP) en el puerto 6970 para el audio del modo auriculares
-   Todos los Roku TV utilizan el puerto 8060 y no se puede cambiar en el TV. Pero si tienes algún tipo de reenvío de puertos configurado y quieres usar un puerto de salida diferente desde Roam, es posible. Sólo necesitas ingresar `[IP]:[Puerto]` en el campo "Dirección IP" en lugar de sólo `[IP]`. Por ejemplo, ingresa `192.168.8.242:8061` y se utilizará el puerto `8061`.