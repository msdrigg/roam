---
hide_table_of_contents: true
---

# Agregar un televisor manualmente

1. Encuentra la dirección IP de tu televisor
    - Enciende tu televisor y navega a **Configuración** > **Red** > **Acerca de**
    - La dirección IP debería parecerse a 10.x.x.x, 172.x.x.x, 173.x.x.x o 192.168.x.x
    - Esta página puede listar una dirección "Gateway" y una "Dirección IP". Asegúrate de NO utilizar la dirección "Gateway"
2. Navega a la configuración de Roam y haz clic en "Agregar un dispositivo manualmente"
3. Nombra tu dispositivo como desees y escribe la IP del dispositivo exactamente como se muestra en el televisor Roku
4. Haz clic en Guardar. Ahora tu Roku debería poder conectarse y funcionar normalmente

## ¿Qué sucede si agregas el televisor manualmente y Roam aún no puede conectarse?

Si Roam aún no puede controlar tu Roku, por favor prueba los siguientes pasos

-   Asegúrate de que tu dispositivo iOS esté conectado a la misma red WiFi que tu televisor Roku
-   Asegúrate de que tu televisor esté encendido
-   Asegúrate de que los permisos de Red Local estén habilitados para Roam (o deshabilítalos y vuelve a habilitarlos si ya están habilitados)
    -   En macOS: Ve a Configuración del Sistema -> Privacidad y Seguridad -> Red Local -> Roam
    -   En iOS: Ve a Configuración -> Aplicaciones -> Roam -> Red Local
-   Consulta posibilidades adicionales aquí [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## ¿Qué sucede si tengo una configuración de red/VPN complicada? ¿Qué protocolos utiliza esta aplicación?

-   Roam utiliza dos protocolos diferentes para comunicarse con el televisor
    -   TCP (HTTP/Websockets) en el puerto 8060 para enviar comandos al televisor
    -   Paquete mágico WOL (multidifusión UDP a la dirección 255.255.255.255) para despertar al televisor de un sueño profundo
-   Todos los televisores Roku utilizan el puerto 8060 y no hay forma de cambiar esto en el lado del televisor. Pero si tienes alguna configuración de reenvío de puerto y quieres usar un puerto de salida diferente desde Roam, es posible. Solo necesitas ingresar `<IP>:<Puerto>` en el campo "Dirección IP" en lugar de solo `<IP>`. Por ejemplo, ingresa `192.168.8.242:8061` y se utilizará el puerto elegido.