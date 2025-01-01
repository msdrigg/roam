---
hide_table_of_contents: true
---

# Mapa de Rota do Roam

## Trabalho Concluído para a Próxima Atualização

-   Adicionados widgets de controlo: Reproduzir, Silenciar, Alterar Volume e Selecionar a partir do centro de controlo!
-   Melhoria no tratamento de campos de texto para muitas apps roku
    -   Abertura automática do campo de texto quando a edição de texto está disponível
    -   Copiar, Cortar, Colar a partir do macOS (com teclado)
    -   Copiar, Cortar, Colar + Edição generalizada no iOS
-   Melhor relatório em volta das permissões da rede local e conectividade
-   Melhoria da funcionalidade do teclado
-   Melhorias na estabilidade da conexão

## Em Breve

-   Adicionar opções de pressão longa às chaves
    -   Pressionar prolongadamente a seta para a direita para ff
    -   Pressionar prolongadamente a seta para a esquerda para rr
    -   Pressionar prolongadamente mute para long-mute
        -   Tornar o +30 configurável para 30, 15, opções de mudo de 60 segundos
        -   Mostrar banner com +30 seg, x para cancelar, indicador de progresso linear em fundo
            -   Mostrar sob o painel de botão principal para que esteja perto de mute
        -   Cancela quando silencia novamente (e também faz chamada para api)
-   Corrigir widgets de macOS

-   Futuro: Fornecer uma visualização minimalista opcional no iOS que replica de perto a visualização do controle remoto siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Suporta também gestos visionos...

## Ideias Futuras Gerais

-   Fazer ícone personalizado para a barra de menus

-   Como fazer voz-para-texto ou comandos de voz gerais?

    -   Precisa de reverter a engenharia do protocolo udp do controle remoto de voz roku
    -   Ou precisa de adicionar texto para discurso personalizado com motor de botão remoto?

-   Automatizar Captura de Captura de Ecrã

    -   Usar UITests para obter capturas de ecrã reais para todos os tamanhos de dispositivos + locais
    -   Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obter as capturas de ecrã nos quadros
    -   Ou outra coisa
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Tente mais truques de teclado no iPad

    -   GCKeyboard para um
    -   FocusEnvironment para 2
    -   Certifique-se de que qualquer solução usada para o iOS não quebra a entrada de texto nas mensagens/entrada de teclado

-   Testes de IU
    -   Testar quando o dispositivo é adicionado que ele aparece no seletor de dispositivos e é selecionado pelo roam
    -   Testar que o usuário pode navegar para configurações -> dispositivos
    -   Testar que o usuário pode navegar para configurações -> mensagens
    -   Testar que o usuário pode navegar para configurações -> informação
    -   Testar que o usuário pode editar/excluir dispositivos
    -   Testar que o usuário pode clicar nos botões uma vez que os dispositivos são adicionados
    -   Teste que o usuário vê o banner para nenhum dispositivo quando ele aparece
    -   Testar que o usuário vê os links para aplicativos
    -   Consultar o swiftdat testingmodelcontainer para modelcontainers
    -   Consultar aqui https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para saber como configurar os testes

## Correções de Erros

-   Descobrir se o ciclo de chamadas para `nextPacket` faz sentido.
    -   Em vez de fazer um ciclo a cada 10ms e esperar que a temporização esteja correta, será que deveria ciclar sobre os pacotes recebidos e tentar agendá-los no momento de host `10ms * globalSequenceNumber + startHostTime` e sampleTime para `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Então posso mudar de um ciclo `for await` pelo relógio para um ciclo `while !Task.isCancelled` com um `Task.sleep` nele.
    -   Então precisamos fazer um ciclo a cada 10 ms e tentar tirar o último pacote e agendá-lo nesse momento
    -   Sempre que fazemos uma sincronização de áudio
        -   Temos lastRenderTime + um pacote de sync
        -   Estimar o número de pacote que devemos estar enviando para fora + o tempo de sync
            -   Render Time + additional

## Melhorar a comunicação ao usuário em torno da gestão de info/estado/capacidades

-   Quando ligar o dispositivo com WOL e não se conectar após 5 segundos, ou quando ligar o dispositivo e falhar imediatamente, mostrar uma mensagem de aviso abaixo da wifi
    -   “Não conseguimos acordar o seu Roku” (Saiba mais) (Não mostrar novamente para este dispositivo), (X)
    -   Saiba mais mostra algumas razões porquê
        -   Não está conectado à mesma rede (Mostrar o último nome de rede do dispositivo. Perguntar se o usuário está conectado a esta rede)
        -   O seu dispositivo está em modo de descanso profundo (não foi desligado recentemente) e não pode ser acordado
            -   O seu dispositivo não suporta WWOL e está conectado ao wifi
            -   O seu dispositivo não suporta WWOL ou WOL
        -   A sua rede não está configurada de uma maneira que nos permita enviar comandos de acordar para o dispositivo
-   Ao clicar num botão desativado, mostrar notificação indicando porque está desativado
    -   Mostrar um indicador de informação no botão para indicar que a informação pode ser recebida quando é clicado?
    -   Modo de fones de ouvido desativado -> porque o dispositivo não suporta o modo de fones de ouvido para esta app
    -   Controle de volume desativado -> porque o áudio está sendo emitido sobre HDMI que não suporta controles de volume?
-   Ao fazer um exame ativo de dispositivos e não encontrar novos, mostrar uma mensagem de aviso abaixo da lista de dispositivos
    -   “Não conseguimos acordar o seu Roku” (Descubra porquê), (X)
    -   Descubra porquê mostra um popup com algumas razões porque isto pode estar acontecendo
        -   Certifique-se de que o seu dispositivo está ligado e conectado à mesma rede wifi que a sua app. Se isto ainda não funcionar, tente adicionar o dispositivo manualmente.
        -   Link https://roam.msd3.io/manually-add-tv.md e https://support.roku.com/article/115001480188 para mais soluções de problemas ou chat
-   Adicionar crachá para supportsWakeOnWLAN e supportsAudioControls

## Para atualizar quando deixar de suportar o iOS 17/macOS 14 (Fev 2026)

-   Ir à volta e remover as etiquetas @available(iOS 18)
-   Usar as características de previsão para injetar dados de amostra nas pré-visualizações
-   SwiftData
    -   Usar a nova macro #Index para modelos
    -   Usar a nova macro #Unique para modelos
    -   Usar exclusão em lote
-   TipKit
    -   Usar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698