---
hide_table_of_contents: true
---

# Adicionar uma TV Manualmente

1. Encontre o Endereço IP da sua TV
    - Ligue a sua TV e navegue até **Definições** > **Rede** > **Sobre**
    - Se não tiver um comando físico ou outra forma de controlar a TV, verifique a interface de administração do seu router doméstico ou a lista de clientes DHCP para encontrar o endereço IP da Roku
    - O Endereço IP deve ter o formato 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Nesta página pode estar listado um endereço "Gateway" e um "Endereço IP". Certifique-se de que NÃO está a usar o endereço "Gateway"
2. Aceda às definições do Roam e clique em "Adicionar dispositivo manualmente"
3. Dê o nome que quiser ao seu dispositivo e insira o IP do dispositivo exatamente como aparece na Roku TV
4. Clique em Guardar. Agora a sua Roku deve conseguir ligar-se e funcionar normalmente

## E se adicionar a TV manualmente, mas o Roam continuar sem conseguir conectar ou a ligação não funcionar corretamente?

Se o Roam continuar sem conseguir controlar a sua Roku, por favor tente os seguintes passos

-   [WatchOS APENAS]: Vá a **Definições -> Sistema -> Definições Avançadas do Sistema -> Controlo por apps móveis** e certifique-se de que está definido como **Permissivo**
-   Certifique-se de que o seu dispositivo iOS está ligado à mesma rede Wi-Fi que a sua Roku TV
-   Certifique-se de que a sua TV está ligada
-   Certifique-se de que a Permissão de Rede Local está ativada para o Roam (ou desative e volte a ativar, caso já esteja ativa)
    -   No macOS: Vá a Definições do Sistema -> Privacidade e Segurança -> Rede Local -> Roam
    -   No iOS: Vá a Definições -> Apps -> Roam -> Rede Local
-   Se a configuração da sua rede doméstica mudou e um dispositivo que antes funcionava deixou de funcionar, elimine o dispositivo guardado do Roam e procure-o novamente
-   Se a Roku não estiver ligada ao Wi-Fi e não tiver um comando físico, siga os passos de ligação para a app móvel da Roku aqui: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Veja mais possibilidades aqui [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## E se eu tiver uma configuração de rede/VPN complicada? Que protocolos utiliza esta app?

-   O Roam utiliza vários protocolos para comunicar com a TV
    -   TCP (HTTP/Websockets) na porta 8060 para enviar comandos para a TV e consultar o estado do dispositivo
    -   Pacote mágico WOL (UDP multicast para o endereço 255.255.255.255) para acordar a TV do modo de suspensão profunda
    -   RDP (UDP) na porta 6970 para o stream de áudio no modo auscultadores
-   Todas as Roku TVs usam a porta 8060 e não existe forma de alterar isso no lado da TV. Mas se tiver algum tipo de encaminhamento de portas configurado e quiser usar uma porta de saída diferente a partir do Roam, é possível. Só precisa de inserir `[IP]:[Porta]` no campo "Endereço IP" em vez de apenas `[IP]`. Por exemplo, insira `192.168.8.242:8061` e será usada a porta `8061`.