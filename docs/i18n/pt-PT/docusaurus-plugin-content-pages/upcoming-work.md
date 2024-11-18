---
hide_table_of_contents: true
---

# Roteiro do Roam

## Trabalho Concluído para a Próxima Atualização

- Adicionados widgets de controle: Play, Mute, Alterar Volume e Selecionar do Centro de Controle!
- Adicionado melhor manuseio de campo de texto para muitos aplicativos roku
    - Auto-abrir campo de texto quando edição de texto está disponível
    - Copiar, Cortar, Colar do macOS
    - Copiar, Cortar, Colar + Edição Generalizado no iOS
- Melhor relatório sobre permissões da rede local e conectividade
- Melhorias na estabilidade da conexão

## Em Breve

- Atual Ongoing
    - Certificar-se de que a inserção de texto no iOS não corta abaixo do teclado (como está fazendo agora)
    - Corrigir widgets do macOS
    - Obter o iOS lançado na app store
        - Aguardar pelo followup do recurso
    - Fazer um teste mais profundo no iOS e no macOS para testar se o sistema reconecta e permanece conectado nos seguintes cenários
        - Após aguardar muito tempo
        - Ao reentrar a partir do fundo
        - Ao ligar a TV a partir do estado OFF
        - Ao reconectar à Internet
        - Ao trocar de aparelho

- Próximo: Adicionar temporizador de mute de +30 segundos com contagem regressiva
    - Manter o mute pressionado por +30 segundos
    - Clicar novamente para desmutar e cancelar
    - Mostrar um indicador abaixo da linha do botão mute 
        - A barra de progresso tem um indicador de progresso linear
        - A barra de progresso tem dois botões: +30 segundos, cancelar
        - Mostrar abaixo do painel principal de botões de modo que fique próximo ao mute
    - Tornar os +30 configuráveis para opções de mute de 30, 15, 60 segundos

- Futuro: Fornecer uma visualização Minimalista opcional no iOS que reproduza de perto a aparência do controle remoto siri
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Suportar gestos visionos também...

## Ideias Futuras Gerais

- Escrever um post de blog sobre o bot do discord e apontar para o meu MessageView
    - Tornar o messageView mais autocontido
- Escrever um post de blog sobre a auto-tradução e a lógica em torno disso
- Escrever um post de blog sobre NWConnection vs URLSession para websockets
- Escrever um post de blog sobre atalhos de teclado personalizados
- Escrever um post de blog sobre ECP Textedit API
- Escrever um post de blog sobre widgets do centro de controle

- Fazer um ícone personalizado da barra de menus

- Como fazer voz-para-texto ou comandos de voz em geral?
    - Necessário fazer engenharia reversa do protocolo udp do controle remoto roku
    - Ou necessário adicionar texto personalizado para fala com motor de botão remoto?

- Automatizar Captura de Screenshot

    - Usar UITests para obter screenshots reais para todos os tamanhos de dispositivo + localidades
    - Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obter os screenshots nas molduras
    - Ou algo mais
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/templates/s/iphone/

- Tentar mais truques de teclado para iPad
    - GCKeyboard para um
    - FocusEnvironment para 2
    - Certificar-se de que a solução usada para iOS não quebra a entrada de texto nas mensagens/entrada de teclado

- UI Tests
    - Testar quando o dispositivo é adicionado que ele aparece no seletor de dispositivos e é selecionado pelo roam
    - Testar que o usuário pode navegar para configurações -> dispositivos
    - Testar que o usuário pode navegar para configurações -> mensagens
    - Testar que o usuário pode navegar para configurações -> sobre
    - Testar que o usuário pode editar/eliminar dispositivos
    - Testar que o usuário pode clicar nos botões uma vez que os dispositivos são adicionados
    - Testar que o usuário vê o banner para nenhum dispositivo quando ele aparece
    - Testar que o usuário vê os applinks
    - Referir-se ao swiftdat testingmodelcontainer para modelcontainers
    - Referir-se a https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para como configurar testes

## Correções de Bugs

- Descobrir se o ciclo de chamadas para `nextPacket` faz sentido.
    - Em vez de fazer um loop a cada 10ms e esperar que o timing esteja correto, devo em vez disso estar fazendo um loop sobre os pacotes recebidos e tentando agendá-los para o horário do host `10ms * globalSequenceNumber + startHostTime` e sampleTime para `sequenceNumber * Int64(lastSampleTime.sampleRate) / pacotesPorSec + startSampleTime`
    - Então eu posso mudar de um loop `para await` sobre o relógio para um loop `while !Task.isCancelled` com um `Task.sleep` nele.
    - Ok, então precisamos fazer um loop a cada 10 ms e tentar retirar o último pacote e então agendá-lo naquele tempo
    - Sempre que fazemos uma sincronia de áudio
        - Nós temos lastRenderTime + um pacote de sincronização
        - Estimar o número do pacote que devemos estar enviando + o tempo de sincronização
            - Render Time + adicional

## Melhorar a comunicação do usuário em torno do gerenciamento de informações/status/capacidades

- Ao ligar o dispositivo com o WOL e não se conectar após 5 segundos, ou ao ligar o dispositivo e falhar imediatamente, mostrar uma mensagem de aviso abaixo da do wifi
    - "Não conseguimos acordar o seu Roku" (Saiba mais), (Não mostrar novamente para este dispositivo), (X)
    - Saiba mais mostra algumas razões possíveis
        - Você não está conectado à mesma rede (Mostrar o último nome da rede do dispositivo. Perguntar ao usuário se ele está conectado a esta rede)
        - Seu dispositivo está em sono profundo (não foi desligado recentemente) e não pode ser despertado
            - Seu dispositivo não suporta WWOL e está conectado ao wifi
            - Seu dispositivo não suporta WWOL ou WOL
        - Sua rede não está configurada para nos permitir enviar comandos de wakeup para o dispositivo
- Ao clicar em um botão desabilitado, mostrar notificação indicando por que ele está desabilitado
    - Mostrar um indicador de info no botão para indicar que informações podem ser recebidas quando ele é clicado?
    - Modo de fones de ouvido desabilitado -> porque o dispositivo não suporta o modo de fones de ouvido para este aplicativo
    - Controle de volume desabilitado -> porque o áudio está sendo enviado por HDMI que não suporta controles de volume?
- Ao fazer a varredura ativa por dispositivos e não encontrar nenhum novo, mostrar uma mensagem de aviso abaixo da lista de dispositivos
    - "Não conseguimos acordar o seu Roku" (Descubra por quê), (X)
    - Descubra mais mostra um popup com algumas razões possíveis para isso estar acontecendo
        - Certifique-se de que seu dispositivo está ligado e conectado à mesma rede wifi que seu aplicativo. Se isso ainda não funcionar, tente adicionar o dispositivo manualmente.
        - Link https://roam.msd3.io/manually-add-tv.md e https://support.roku.com/article/115001480188 para mais solução de problemas ou bate-papo
- Adicionar crachá para supportsWakeOnWLAN e supportsMute

## Para atualizar quando deixar de suportar iOS 17/macOS 14 (fevereiro 2026)

- Ir em volta e remover @ available(iOS 18) tags
- Usar traços de pré-visualização para injetar dados de amostra em pré-visualizações
- SwiftData
    - Usar novo macro #Index para modelos
    - Usar novo macro #Unique para modelos
    - Usar exclusão em lote
- TipKit
    - Usar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
