---
hide_table_of_contents: true
---

# Añadir un televisor manualmente

1. Encuentra la dirección IP de tu televisor
    - Enciende tu televisor y navega a **Configuración** > **Red** > **Acerca de**
    - La dirección IP debería ser similar a 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - Esta página puede listar una dirección "Gateway" y una "Dirección IP". Asegúrate de NO usar la dirección "Gateway".
2. Navega a la configuración de Roam y haz clic en "Añadir un dispositivo manualmente".
3. Nombra tu dispositivo como quieras, e introduce la dirección IP del dispositivo exactamente como aparece en el televisor Roku.
4. Haz clic en Guardar. Ahora tu Roku debería poder conectarse y funcionar normalmente.

## ¿Qué pasa si añades el televisor manualmente y Roam sigue sin poder conectarse?

Si Roam sigue sin poder controlar tu Roku, por favor intenta los siguientes pasos:

-   Asegúrate de que tu dispositivo iOS está conectado a la misma red WiFi que tu Roku TV.
-   Asegúrate de que tu televisor esté encendido.
-   Asegúrate de que los permisos de Red Local estén habilitados para Roam (o inhabilita y habilita de nuevo si ya está habilitado).
    -   En macOS: Ve a Configuración del Sistema -> Privacidad y Seguridad -> Red Local -> Roam
    -   En iOS: Ve a Ajustes -> Aplicaciones -> Roam -> Red Local
-   Ve más posibilidades en [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## ¿Qué pasa si tengo una red/VPN complicada? ¿Qué protocolos utiliza esta aplicación?

-   Roam utiliza dos protocolos diferentes para comunicarse con el televisor:
    -   TCP (HTTP/Websockets) en el puerto 8060 para enviar comandos al televisor.
    -   Paquete mágico WOL (UDP multicast a la dirección 255.255.255.255) para despertar al televisor de un sueño profundo.
-   Todos los televisores Roku usan el puerto 8060 y no hay manera de cambiar esto desde el televisor. Pero si tienes configurado un reenvío de puertos y quieres usar un puerto de salida diferente desde Roam, es posible. Solo necesitas introducir `<IP>:<Puerto>` en el campo "Dirección IP" en lugar de solo `<IP>`. Por ejemplo, introduce `192.168.8.242:8061` y se utilizará el puerto elegido.
