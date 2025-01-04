---
hide_table_of_contents: true
---

# Adicionando uma TV Manualmente

1. Encontre o endereço IP da sua TV
    - Ligue sua TV e navegue até **Configurações** > **Rede** > **Sobre**
    - O endereço IP deve parecer com 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Esta página pode listar um endereço "Gateway" e um "Endereço IP". Certifique-se de NÃO usar o endereço "Gateway"
2. Navegue até as configurações de Roam e clique em "Adicionar um dispositivo manualmente"
3. Nomeie seu dispositivo como quiser e digite o IP do dispositivo exatamente como mostrado na TV Roku
4. Clique em Salvar. Agora o seu Roku deve ser capaz de conectar e funcionar normalmente

## E se você adicionar a TV manualmente e a Roam ainda não conseguir conectar?

Se a Roam ainda não conseguir controlar a sua Roku, por favor, tente os seguintes passos

-   Certifique-se de que seu dispositivo iOS está conectado à mesma rede WiFi que sua TV Roku
-   Certifique-se de que sua TV está ligada
-   Certifique-se de que as Permissões da Rede Local estão habilitadas para o Roam (ou desative e reative se já estiver habilitado)
    -   No macOS: Vá para Configurações do Sistema -> Privacidade e Segurança -> Rede Local -> Roam
    -   No iOS: Vá para Configurações -> Apps -> Roam -> Rede Local
-   Veja possibilidades adicionais aqui [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## E se eu tiver uma rede/VPN complicada? Quais protocolos este aplicativo usa?

-   Roam usa dois protocolos diferentes para se comunicar com a TV
    -   TCP (HTTP/Websockets) na porta 8060 para enviar comandos para a TV
    -   WOL magic packet (UDP multicast para o endereço 255.255.255.255) para acordar a TV do sono profundo
-   Todas as TVs Roku usam a porta 8060 e não há como mudar isso do lado da TV. Mas se você tem algum tipo de encaminhamento de porta configurado e quer usar uma porta de saída diferente do Roam, é possível. Você só precisa inserir `<IP>:<Porta>` no campo "Endereço IP" em vez de apenas `<IP>`. Por exemplo, digite `192.168.8.242:8061` e a porta escolhida será usada.
