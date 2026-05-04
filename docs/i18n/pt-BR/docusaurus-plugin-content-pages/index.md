---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## Sobre o Roam

O Roam oferece tudo o que você quer e nada do que não precisa

-   Funciona no Mac, iPhone, iPad, Apple Watch, Vision Pro ou Apple TV!
-   Integração inteligente com as plataformas: use atalhos de teclado no Mac, e os botões de volume do aparelho para controlar o volume da TV no iOS
-   Use atalhos e widgets para controlar sua TV sem precisar abrir o app!
-   Suporte ao modo de fones de ouvido (escuta privada) no Mac, iPad, iPhone, VisionOS e Apple TV (ouça o áudio da sua TV pelo seu dispositivo)
-   Descubra dispositivos na sua rede local assim que abrir o app
-   Design intuitivo com o sistema nativo SwiftUI da Apple
-   Rápido e leve: menos de 8 MB em todos os dispositivos e abre em menos de meio segundo!
-   Código aberto (https://github.com/msdrigg/roam)

## Funcionalidades

-   Controles remotos
    -   O Roam inclui todos os controles clássicos do controle remoto Roku, como botões direcionais, selecionar, voltar, início, play/pausa e controles relacionados à TV quando o Roku é compatível.
    -   Os controles de volume podem não funcionar em Roku Sticks, pois são dispositivos apenas HDMI e não conseguem controlar o volume da TV pelos comandos de rede do Roku no Roam.
-   Entrada de teclado
    -   No macOS, não há botão de teclado. Quando a janela do Roam está em foco, o teclado do Mac já funciona automaticamente com a TV.
    -   No iOS e iPadOS, há um botão de teclado no topo do controle remoto.
    -   O watchOS não tem funcionalidade de teclado por enquanto.
    -   Alguns apps do Roku ignoram a entrada do teclado via apps remotos. O Prime Video é um exemplo conhecido onde pode não funcionar porque o app Roku não aceita essa entrada.
-   Modo fones de ouvido/escuta privada
    -   O escuta privada reproduz o áudio da TV pelo seu dispositivo em modelos Roku compatíveis.
    -   O modo escuta privada é compatível no Roam para Mac, iPad, iPhone, VisionOS e Apple TV, mas não funciona em todos os modelos de Roku TV.

## Problemas Comuns

-   O que fazer se o Roam não encontrar minha TV automaticamente?
    -   [Veja aqui](/manually-add-tv)
-   O Roam não está funcionando corretamente no meu Apple Watch
    -   Acesse **Configurações -> Sistema -> Configurações Avançadas do Sistema -> Controle por aplicativos móveis** e certifique-se de que está definido como **Permissivo**
-   Por que o modo fones de ouvido (escuta privada) não funciona na minha TV?
    -   Atualmente, o modo fones de ouvido não está funcionando em algumas TVs. Se o modo fones de ouvido não funcionar com o Roam, mas funcionar com o app oficial do Roku, por favor envie o nome do modelo do seu Roku e outras informações relevantes por e-mail para [roam-support@msd3.io](mailto:roam-support@msd3.io). Seu relato ajudará a encontrar a causa do problema e resolvê-lo.
-   E se eu tiver outro problema ou quiser enviar feedback?
    -   Se for um bug, o ideal é abrir um relatório de feedback pelo aplicativo:
        -   Abra o app Roam e vá até a página de configurações
        -   Clique em "Enviar feedback". Será gerado um relatório de diagnóstico que pode ser compartilhado com o suporte do Roam (roam-support@msd3.io)
        -   Se o app estiver travando, ative a coleta de dados em Configurações -> Privacidade & Segurança -> Análises e Melhorias
            -   Ative "Compartilhar análises do iPhone & Watch" e "Compartilhar com desenvolvedores de apps" para que a Apple me avise quando o app travar
    -   Se for uma sugestão de nova função, envie um e-mail (roam-support@msd3.io), converse diretamente comigo pelo app Roam (Configurações -> Fale com o Desenvolvedor) ou entre no [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Por que as setas do teclado às vezes não funcionam no iPad?
    -   Isso acontece porque o iPadOS às vezes assume o controle das setas para navegar entre os botões da tela, antes do Roam identificá-las
    -   Você pode contornar isso acessando Configurações -> Acessibilidade -> Teclados e desativando "Acesso Completo ao Teclado" ou indo em Configurações -> Acessibilidade -> Teclados -> Acesso Completo ao Teclado -> Comandos -> Básico e desativando os comandos "Mover para cima", "Mover para baixo", "Mover para a esquerda" e "Mover para a direita".
-   Por que o que eu digito no teclado não aparece na TV?
    -   Em alguns apps do Roku, a entrada pelo teclado físico é ignorada. Você pode testar se é um bug do Roam tentando a entrada de texto pelo app oficial do Roku, para ver se funciona.
    -   No macOS, não há botão de teclado porque o teclado do Mac já funciona automaticamente com a TV ao focar a janela do Roam. No iOS e no iPadOS, use o botão de teclado no topo do controle remoto. O watchOS não suporta teclado no momento.
    -   Apps com bugs conhecidos:
        -   Prime Video
-   Por que o Roam funciona no meu iPhone e Mac, mas não no Apple Watch?
    -   O app no WatchOS se conecta à TV utilizando a API ECP da TV, que deve estar ativada em alguns modelos Roku TV. Para ativar, vá em **Configurações -> Sistema -> Configurações Avançadas do Sistema -> Controle por aplicativos móveis** e certifique-se de que o "Acesso à Rede" está como "Permissivo"

## Outros Recursos

Se tiver dúvidas ou problemas, entre em contato pelo e-mail: [roam-support@msd3.io](mailto:roam-support@msd3.io). Você também pode conversar diretamente comigo no app Roam (Configurações -> Fale com o Desenvolvedor) ou participar do [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Política de Privacidade](/privacy)
-   [Repositório principal no GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Baixe na app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roteiro de desenvolvimento](/upcoming-work)
-   [Registro de mudanças](/changes)
-   [Dispositivos Roku testados](/tested-tvs)