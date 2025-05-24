---
hide_table_of_contents: true
---

# Adicionando uma TV Manualmente

1. Encontre o Endereço IP da sua TV
    - Ligue sua TV e navegue até **Configurações** > **Rede** > **Sobre**
    - O endereço IP deve se parecer com 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Esta página pode listar um endereço de "Gateway" e um "Endereço IP". Certifique-se de NÃO usar o endereço "Gateway"
2. Acesse as configurações do Roam e clique em "Adicionar um dispositivo manualmente"
3. Dê o nome que desejar ao seu dispositivo e insira o endereço IP exatamente como mostrado na Roku TV
4. Clique em Salvar. Agora seu Roku deve conseguir conectar e funcionar normalmente

## E se você adicionar a TV manualmente e o Roam ainda não conseguir conectar ou a conexão não funcionar corretamente?

Se o Roam ainda não conseguir controlar sua Roku, tente os seguintes passos

-   [Somente WatchOS]: Vá em **Configurações -> Sistema -> Configurações Avançadas do Sistema -> Controle por aplicativos móveis** e certifique-se que está definido como **Permissivo**
-   Certifique-se de que seu dispositivo iOS está conectado à mesma rede Wi-Fi que sua Roku TV
-   Certifique-se de que sua TV está ligada
-   Certifique-se de que as Permissões de Rede Local estão ativadas para o Roam (ou desative e ative novamente se já estiver ativado)
    -   No macOS: Vá em Ajustes do Sistema -> Privacidade e Segurança -> Rede Local -> Roam
    -   No iOS: Vá em Ajustes -> Apps -> Roam -> Rede Local
-   Veja possibilidades adicionais aqui [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## E se eu tiver uma configuração de rede/VPN complicada? Quais protocolos este app utiliza?

-   O Roam usa vários protocolos diferentes para se comunicar com a TV
    -   TCP (HTTP/Websockets) na porta 8060 para enviar comandos para a TV e consultar o estado do dispositivo
    -   Pacote mágico WOL (UDP multicast para o endereço 255.255.255.255) para acordar a TV do modo de sono profundo
    -   RDP (UDP) na porta 6970 para o streaming de áudio no modo fones de ouvido
-   Todas as Roku TVs utilizam a porta 8060 e não há como alterar isso no lado da TV. Mas, se você possui algum tipo de encaminhamento de porta configurado e deseja usar uma porta de saída diferente pelo Roam, isso é possível. Basta inserir `[IP]:[Porta]` no campo "Endereço IP" em vez de apenas `[IP]`. Por exemplo, insira `192.168.8.242:8061` e a porta `8061` será utilizada.