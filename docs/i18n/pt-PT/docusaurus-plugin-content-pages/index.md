---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Sobre o Roam

O Roam oferece tudo o que queres e nada do que não queres

-   Funciona em Mac, iPhone, iPad, Apple Watch, Vision Pro ou Apple TV!
-   Integração inteligente com o sistema, com atalhos de teclado no Mac, utilizando os botões de volume físico para controlar o volume da TV no iOS
-   Usa atalhos e widgets para controlares a TV sem nunca abrir a app!
-   Suporte para modo auscultadores (ou escuta privada) no Mac, iPad, iPhone, VisionOS e Apple TV (ouve o áudio da tua TV pelo teu dispositivo)
-   Descobre dispositivos na tua rede local assim que abres a app
-   Design intuitivo com o sistema nativo SwiftUI da Apple
-   Rápido e leve, menos de 8 MB em todos os dispositivos e abre em menos de meio segundo!
-   Código aberto (https://github.com/msdrigg/roam)

## Funcionalidades

-   Comandos remotos
    -   O Roam inclui os controlos normais do comando Roku, como botões direcionais, selecionar, voltar, início, play/pausa e outros controlos relacionados da TV quando o Roku os suporta.
    -   Os controlos de volume podem não funcionar nos Roku Sticks porque são dispositivos apenas HDMI e não conseguem controlar o volume da TV através dos comandos de rede do Roku do Roam.
-   Introdução via teclado
    -   No macOS, não existe botão de teclado. Quando a janela do Roam está em foco, o teclado do Mac funciona automaticamente com a TV.
    -   No iOS e iPadOS, existe um botão de teclado no topo do comando.
    -   O watchOS não tem funcionalidade de teclado de momento.
    -   Algumas aplicações Roku ignoram a introdução de teclado por apps remotas. Por exemplo, no Prime Video pode não funcionar porque a app Roku não aceita esse tipo de entrada.
-   Modo auscultadores/escuta privada
    -   A escuta privada permite ouvir o áudio da TV através do teu dispositivo nos Roku compatíveis.
    -   Este modo é suportado no Roam para Mac, iPad, iPhone, VisionOS e Apple TV, mas pode não funcionar em todas as televisões Roku.

## Problemas Comuns

-   O que posso fazer se o Roam não detetar automaticamente a minha TV?
    -   [Vê aqui](/manually-add-tv)
-   O Roam não está a funcionar corretamente no meu Apple Watch
    -   Por favor, vai a **Definições -> Sistema -> Definições Avançadas do Sistema -> Controlo por apps móveis** e certifica-te que está definido como **Permissivo**
-   Porque é que o modo auscultadores (escuta privada) não funciona na minha TV?
    -   De momento, este modo não funciona em algumas TVs. Se não funcionar no Roam, mas funcionar na app oficial da Roku, partilha o modelo da tua Roku e outras informações relevantes por email para [roam-support@msd3.io](mailto:roam-support@msd3.io). O teu relato ajudará a identificar o problema para que possa ser corrigido.
-   O que faço se tiver outro problema ou quiser apenas dar feedback?
    -   Se for um erro, o melhor será fazer um reporte de feedback a partir da aplicação
        -   Abre a app Roam e vai à página de definições
        -   Clica em "Enviar feedback". Isto vai gerar um relatório de diagnóstico que pode ser partilhado com o suporte do Roam (roam-support@msd3.io)
        -   Se a tua app estiver a bloquear, certifica-te também de que as análises estão ativas em Definições -> Privacidade & Segurança -> Análises & Melhorias
            -   Ativa "Partilhar Análise do iPhone & Watch" e depois ativa "Partilhar com Desenvolvedores" para que a Apple me notifique em caso de bloqueio da tua app
    -   Se for um pedido de nova funcionalidade, podes enviar um email (roam-support@msd3.io), falar comigo diretamente na app Roam (Definições -> Falar com o Desenvolvedor) ou entrar no [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Porque é que, por vezes, as teclas das setas não funcionam no iPad?
    -   Isto acontece porque o iPadOS, por vezes, controla as setas para navegar pelos botões de ecrã antes que a app as possa detetar
    -   Podes contornar isto indo a Definições -> Acessibilidade -> Teclados e desativando o "Acesso Total ao Teclado"; em alternativa, podes ir a Definições -> Acessibilidade -> Teclados -> Acesso Total ao Teclado -> Comandos -> Básico e desativar os comandos "Mover Para Cima", "Mover Para Baixo", "Mover Para a Esquerda" e "Mover Para a Direita"
-   Porque é que ao escrever no meu teclado não aparece nada na TV?
    -   Em algumas apps Roku, a app ignora a entrada via teclado físico. Podes testar se é um bug do Roam ou da app usando a funcionalidade de teclado na app oficial Roku e ver se funciona
    -   No macOS, não há botão de teclado porque o teclado do Mac funciona automaticamente com a TV quando a janela do Roam está em foco. No iOS e iPadOS, usa o botão de teclado no topo do comando. O watchOS não suporta introdução de teclado de momento.
    -   Apps com problemas conhecidos
        -   Prime Video
-   Porque é que o Roam funciona no meu iPhone e Mac, mas não funciona no Apple Watch?
    -   A app WatchOS liga-se à TV através da API ECP da TV, que tem de estar ativa em algumas televisões Roku. Para a ativares, vai a **Definições -> Sistema -> Definições Avançadas do Sistema -> Controlo por apps móveis** e certifica-te que o "Acesso à Rede" está em "Permissivo"

## Outros Recursos

Se tiveres dúvidas ou problemas, contacta-me em: [roam-support@msd3.io](mailto:roam-support@msd3.io). Também podes falar comigo diretamente através da app Roam (Definições -> Falar com o Desenvolvedor) ou entrar no [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Política de Privacidade](/privacy)
-   [Repositório Principal no GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Descarregar na App Store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roteiro](/upcoming-work)
-   [Registo de Alterações](/changes)
-   [Dispositivos Roku Testados](/tested-tvs)