---
hide_table_of_contents: true
---

# Adicionando uma TV Manualmente

1. Encontre o Endereço IP da sua TV
    - Ligue sua TV e vá até **Configurações** > **Rede** > **Sobre**
    - Se você não tiver um controle remoto físico ou outra maneira de controlar a TV, verifique a interface de administração do seu roteador doméstico ou a lista de clientes DHCP para encontrar o endereço IP do Roku
    - O endereço IP deve ter o formato 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Esta página pode mostrar um endereço de "Gateway" e um "Endereço IP". Certifique-se de NÃO usar o endereço do "Gateway"
2. Vá até as configurações do Roam e clique em "Adicionar um dispositivo manualmente"
3. Dê o nome que desejar ao seu dispositivo e insira o IP exatamente como mostrado na TV Roku
4. Clique em Salvar. Agora o seu Roku deve conseguir conectar e funcionar normalmente

## E se você adicionar a TV manualmente e o Roam ainda não conseguir conectar ou a conexão não funcionar direito?

Se o Roam ainda não conseguir controlar o seu Roku, tente os passos abaixo:

-   [Somente WatchOS]: Vá até **Configurações -> Sistema -> Configurações Avançadas do Sistema -> Controle por aplicativos móveis** e certifique-se de que está definido como **Permissivo**
-   Garanta que seu dispositivo iOS esteja conectado à mesma rede Wi-Fi que sua TV Roku
-   Certifique-se de que sua TV está ligada
-   Verifique se as Permissões de Rede Local estão ativadas para o Roam (ou desative e reative se já estiver ativo)
    -   No macOS: Vá até Ajustes do Sistema -> Privacidade e Segurança -> Rede Local -> Roam
    -   No iOS: Vá até Ajustes -> Apps -> Roam -> Rede Local
-   Se a configuração da sua rede doméstica mudou e um dispositivo que funcionava parou de funcionar, apague o dispositivo salvo do Roam e faça a busca novamente
-   Se o Roku não estiver conectado ao Wi-Fi e você não tiver um controle remoto físico, siga os passos para conexão pelo app móvel do Roku aqui: [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)
-   Veja outras possibilidades aqui [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## E se eu tiver uma configuração de rede/VPN complicada? Quais protocolos este app utiliza?

-   O Roam utiliza vários protocolos diferentes para se comunicar com a TV:
    -   TCP (HTTP/Websockets) na porta 8060 para enviar comandos à TV e consultar o estado do dispositivo
    -   Pacote mágico WOL (UDP multicast para o endereço 255.255.255.255) para acordar a TV do modo de sono profundo
    -   RDP (UDP) na porta 6970 para o áudio do modo fones de ouvido
-   Todas as TVs Roku usam a porta 8060 e não há como alterar isso no lado da TV. Mas, se você possui algum redirecionamento de portas configurado e quiser usar uma porta de saída diferente a partir do Roam, isso é possível. Basta digitar `[IP]:[Porta]` no campo "Endereço IP" ao invés de apenas `[IP]`. Por exemplo, informe `192.168.8.242:8061` e será utilizada a porta `8061`.