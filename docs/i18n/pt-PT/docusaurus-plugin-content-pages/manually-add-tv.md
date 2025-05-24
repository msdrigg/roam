---
hide_table_of_contents: true
---

# Adicionar uma TV Manualmente

1. Encontre o Endereço IP da sua TV
    - Ligue a sua TV e navegue até **Definições** > **Rede** > **Sobre**
    - O Endereço IP deverá ter o formato 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Esta página pode mostrar um endereço de "Gateway" e um "Endereço IP". Certifique-se de que NÃO está a usar o endereço "Gateway"
2. Vá às definições do Roam e clique em "Adicionar um dispositivo manualmente"
3. Dê o nome que quiser ao seu dispositivo e introduza o IP exatamente como aparece na Roku TV
4. Clique em Guardar. Agora o seu Roku deverá conseguir ligar-se e funcionar normalmente

## E se adicionar a TV manualmente e o Roam continuar sem conseguir ligar-se ou a ligação não funcionar corretamente?

Se o Roam ainda não conseguir controlar o seu Roku, por favor tente os seguintes passos

-   [WatchOS APENAS]: Vá a **Definições -> Sistema -> Definições Avançadas do Sistema -> Controlo por aplicações móveis** e certifique-se de que está definido como **Permissivo**
-   Certifique-se de que o seu dispositivo iOS está ligado à mesma rede WiFi que a sua Roku TV
-   Certifique-se de que a sua TV está ligada
-   Certifique-se de que a Permissão de Rede Local está ativada para o Roam (ou desative e volte a ativar se já estiver ativada)
    -   No macOS: Vá a Definições do Sistema -> Privacidade e Segurança -> Rede Local -> Roam
    -   No iOS: Vá a Definições -> Apps -> Roam -> Rede Local
-   Veja mais possibilidades adicionais aqui [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## E se eu tiver uma configuração de rede/VPN complicada? Que protocolos utiliza esta app?

-   O Roam utiliza vários protocolos diferentes para comunicar com a TV
    -   TCP (HTTP/Websockets) na porta 8060 para enviar comandos para a TV e consultar o estado do dispositivo
    -   Pacote mágico WOL (UDP multicast para o endereço 255.255.255.255) para acordar a TV do modo de suspensão profunda
    -   RDP (UDP) na porta 6970 para o áudio do modo auscultadores
-   Todas as Roku TV utilizam a porta 8060 e não há forma de alterar isto no lado da TV. Mas, se tiver algum encaminhamento de portos configurado e quiser usar uma porta de saída diferente a partir do Roam, é possível. Só tem de introduzir `[IP]:[Porta]` no campo "Endereço IP" em vez de apenas `[IP]`. Por exemplo, introduza `192.168.8.242:8061` e será usada a porta `8061`.