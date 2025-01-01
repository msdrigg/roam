---
hide_table_of_contents: true
---

# Planejamento do Roam

## Trabalho Concluído para Próxima Atualização

-   Adicionado widgets de controle: Play, Mudo, Alterar Volume e Selecionar do Central de Controle!
-   Melhor manipulação de campos de texto para muitos aplicativos Roku
    -   Campo de texto de abertura automática quando a edição de texto está disponível
    -   Copiar, cortar, colar do macOS (com teclado)
    -   Copiar, cortar, colar + Edição generalizada no iOS
-   Melhorias na geração de relatórios em torno de permissões de rede local e conectividade
-   Aprimoramento da funcionalidade do teclado
-   Melhorias na estabilidade da conexão

## Em Breve

-   Adicionar opções de pressão longa às teclas
    -   Pressione longamente a seta da direita para avançar rápido
    -   Pressione longamente a seta da esquerda para retroceder
    -   Pressione longamente o botão mudo para silenciar por um longo tempo
        -   Tornar a opção de +30 configurável para 30, 15, 60 opções de mudo por segundo
        -   Mostrar banner com +30 seg, x para cancelar, indicador de progresso linear de fundo
            -   Exibir abaixo do painel de botões principal para ficar próximo ao botão mudo
        -   Cancela ao clicar no botão mudo novamente (e também faz uma chamada de API)
-   Resolver problemas com os widgets do macOS

-   Futuro: Fornecer uma visualização Minimalista opcional no iOS que reproduza de perto a vista do controle remoto Siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Oferecer suporte a gestos visionos também...

## Ideias Gerais Futuras

-   Fazer ícone personalizado da barra de menus

-   Como fazer voz para texto ou comandos de voz gerais?

    -   Necessário decifrar o protocolo udp do controle remoto de voz Roku
    -   Ou é necessário adicionar texto personalizado para voz com o motor de botão remoto?

-   Automatizar Captura de Screenshot

    -   Usar UITests para obter capturas de tela reais para todos os tamanhos de dispositivo e localizações
    -   Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obter as capturas de tela nos quadros
    -   Ou algo mais
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Experimentar mais truques de teclado no iPad

    -   GCKeyboard para um
    -   FocusEnvironment para dois
    -   Garantir que a solução utilizada para o iOS não prejudique a entrada de texto nas mensagens/entrada de teclado

-   Testes da Interface do Usuário
    -   Testar quando o dispositivo é adicionado que ele aparece no seletor de dispositivo e é selecionado pelo roam
    -   Testar se o usuário pode navegar para configurações -> dispositivos
    -   Testar se o usuário pode navegar para configurações -> mensagens
    -   Testar se o usuário pode navegar para configurações -> sobre
    -   Testar se o usuário pode editar/excluir dispositivos
    -   Testar se o usuário pode clicar nos botões uma vez que os dispositivos são adicionados
    -   Testar se o usuário vê o banner para nenhum dispositivo quando ele aparece
    -   Testar se o usuário vê os links do aplicativo
    -   Consultar o swiftdat testingmodelcontainer para modelcontainers
    -   Consultar aqui https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para como configurar os testes

## Correções de Bugs

-   Descobrir se o ciclo de chamadas para `nextPacket` faz sentido.
    -   Em vez de fazer loop a cada 10 ms e esperar que o tempo esteja correto, eu deveria fazer loop pelos pacotes recebidos e tentar agendá-los no horário do host `10ms * número de sequência global + horário inicial do host` e sampleTime para `número de sequência * Int64 (últimoSampleTime.sampleRate) / pacotesPorSeg + startSampleTime`
    -   Então eu posso mudar de um loop `para aguardar` sobre o relógio para um loop `while !Task.isCancelled` com um `Task.sleep` nele.
    -   Ok, então precisamos fazer loop a cada 10 ms e tentar pegar o último pacote e, em seguida, agendá-lo nesse momento
    -   Sempre que fazemos uma sincronização de áudio
        -   Temos lastRenderTime + um pacote de sincronização
        -   Estimar o número do pacote que devemos estar enviando + o tempo de sincronização
            -   Tempo de Renderização + adicional

## Melhorar as mensagens do usuário em torno do gerenciamento de info/status/capabilidades

-   Ao ligar o dispositivo com WOL e não se conectar após 5 segundos, ou quando ligar o dispositivo e falhar imediatamente, mostrar uma mensagem de aviso abaixo do wifi
    -   “Não conseguimos acordar seu Roku” (Saiba mais) (Não mostrar novamente para este dispositivo), (X)
    -   Saiba mais mostra algumas razões possíveis
        -   Você não está conectado à mesma rede (Mostrar o último nome da rede do dispositivo. Pergunte se o usuário está conectado a esta rede)
        -   Seu dispositivo está em sono profundo (não foi desligado recentemente) e não pode ser acordado
            -   Seu dispositivo não suporta WWOL e está conectado ao wifi
            -   O seu dispositivo não suporta WWOL ou WOL
        -   Sua rede não está configurada de uma maneira que nos permita enviar comandos de despertar para o dispositivo
-   Ao clicar em um botão desativado, exibir notificação indicando por que ele está desativado
    -   Mostrar um indicador de informação no botão para indicar que as informações podem ser recebidas quando ele é clicado?
    -   Modo de fones de ouvido desativado -> porque o dispositivo não suporta o modo de fones de ouvido para este aplicativo
    -   Controle de volume desativado -> porque o áudio está sendo transmitido por HDMI que não suporta controles de volume?
-   Quando estiver verificando ativamente os dispositivos e não encontrar novos, mostrar uma mensagem de aviso abaixo da lista de dispositivos
    -   “Não conseguimos acordar o seu Roku” (Saiba por quê), (X)
    -   Saiba mais mostra um pop-up com algumas razões possíveis para isso estar acontecendo
        -   Certifique-se de que o dispositivo está ligado e conectado à mesma rede wifi que o seu aplicativo. Se isso ainda não funcionar, tente adicionar o dispositivo manualmente.
        -   Link https://roam.msd3.io/adicionar-tv-manualmente.md e https://support.roku.com/article/115001480188 para mais solução de problemas ou chat
-   Adicionar crachá para supportsWakeOnWLAN e supportsAudioControls

## Para atualizar ao descartar o suporte para iOS 17/macOS 14 (Fev 2026)

-   Vá por aí e remova as tags @available(iOS 18)
-   Use traits de pré-visualização para injetar dados de amostra em pré-visualizações
-   SwiftData
    -   Use a nova macro #Index para modelos
    -   Use a nova macro #Unique para modelos
    -   Use a exclusão em lote
-   TipKit
    -   Use CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
