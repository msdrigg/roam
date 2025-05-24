---
hide_table_of_contents: true
---

# Agregar manualmente un televisor

1. Encuentra la dirección IP de tu televisor
    - Enciende tu televisor y navega a **Configuración** > **Red** > **Acerca de**
    - La dirección IP debería verse como 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - Esta página puede mostrar una dirección "Gateway" y una "Dirección IP". Asegúrate de NO usar la dirección "Gateway"
2. Ve a la configuración de Roam y haz clic en "Agregar un dispositivo manualmente"
3. Nombra tu dispositivo como desees e ingresa la dirección IP exactamente como aparece en tu Roku TV
4. Haz clic en Guardar. Ahora tu Roku debería poder conectarse y funcionar normalmente

## ¿Qué pasa si agregas el televisor manualmente y Roam aún no puede conectarse o la conexión no funciona correctamente?

Si Roam todavía no puede controlar tu Roku, por favor intenta los siguientes pasos

-   [Solo WatchOS]: Ve a **Configuración -> Sistema -> Configuración avanzada del sistema -> Control por aplicaciones móviles** y asegúrate de que esté en **Permisivo**
-   Asegúrate de que tu dispositivo iOS esté conectado a la misma red WiFi que tu Roku TV
-   Asegúrate de que tu televisor esté encendido
-   Asegúrate de que los permisos de Red Local estén habilitados para Roam (o desactívalos y vuelve a activarlos si ya estaban activados)
    -   En macOS: Ve a Configuración del Sistema -> Privacidad y seguridad -> Red local -> Roam
    -   En iOS: Ve a Configuración -> Apps -> Roam -> Red local
-   Consulta otras posibilidades aquí [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## ¿Qué pasa si tengo una configuración de red o VPN complicada? ¿Qué protocolos usa esta aplicación?

-   Roam utiliza varios protocolos diferentes para comunicarse con el televisor
    -   TCP (HTTP/Websockets) en el puerto 8060 para enviar comandos al televisor y consultar el estado del dispositivo
    -   Paquete mágico WOL (UDP multicast a la dirección 255.255.255.255) para encender el televisor desde un estado de suspensión profunda
    -   RDP (UDP) en el puerto 6970 para la transmisión de audio en el modo de auriculares
-   Todos los Roku TV utilizan el puerto 8060 y no hay manera de cambiar esto en el televisor. Pero si tienes algún tipo de reenvío de puertos y deseas usar un puerto de salida diferente desde Roam, es posible. Solo tienes que ingresar `[IP]:[Puerto]` en el campo "Dirección IP" en lugar de solo `[IP]`. Por ejemplo, ingresa `192.168.8.242:8061` y se usará el puerto `8061`.