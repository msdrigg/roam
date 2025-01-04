---
hide_table_of_contents: true
---

# Adicionar um TV Manualmente

1. Encontre o endereço IP da sua TV
    - Ligue a sua TV e navegue até **Definições** > **Rede** > **Sobre**
    - O endereço IP deve parecer algo como 10.x.x.x, 172.x.x.x, 173.x.x.x ou 192.168.x.x
    - Esta página pode listar um endereço "Gateway" e um "Endereço IP". Certifique-se de que NÃO está a utilizar o endereço "Gateway"
2. Navegue até às definições de Roam e clique em "Adicionar um dispositivo manualmente"
3. Dê o nome que quiser ao seu dispositivo e introduza exatamente como está no Roku TV o IP do dispositivo
4. Clique em Salvar. Agora o seu Roku deverá poder conectar e funcionar normalmente

## E se adicionar o TV manualmente e o Roam ainda não conseguir ligar?

Se o Roam ainda não consegue controlar o seu Roku, por favor tente os seguintes passos

- Certifique-se de que o seu dispositivo iOS está ligado à mesma rede WiFi que a sua TV Roku
- Certifique-se de que a sua TV está ligada
- Garanta que as permissões de rede local estão habilitadas para Roam (ou desative e reative se já estiverem habilitadas)
    - Em macOS: Vá a Definições do Sistema -> Privacidade e Segurança -> Rede Local -> Roam
    - Em iOS: Vá a Definições -> Aplicações -> Roam -> Rede Local
- Veja possibilidades adicionais aqui [https://support.roku.com/article/115001480188](https://support.roku.com/article/115001480188)

## E se eu tiver uma configuração complicada de rede/VPN? Que protocolos é que esta aplicação utiliza?

- O Roam usa dois protocolos diferentes para se comunicar com a TV
    - TCP (HTTP/Websockets) na porta 8060 para enviar comandos para a TV
    - Pacote mágico WOL (UDP multicast para o endereço 255.255.255.255) para acordar a TV de um sono profundo
- Todas as TVs Roku utilizam a porta 8060 e não há maneira de mudar isso do lado da TV. Mas se tiver algum tipo de configuração de reencaminhamento de porta e quiser usar uma porta de saída diferente do Roam, isso é possível. Só precisa de inserir `<IP>:<Port>` no campo "Endereço IP" em vez de apenas `<IP>`. Por exemplo, insira `192.168.8.242:8061` e a porta escolhida será utilizada.