---
hide_table_of_contents: true
---

# Roteiro do Roam

## Trabalho concluído para a próxima atualização

- Adicionado widgets de controle: Reproduzir, Silenciar, Alterar volume e Selecionar do centro de controle!
- Melhoria no tratamento de campos de texto para muitos aplicativos roku
    - Abertura automática do campo de texto quando a edição de texto está disponível
    - Copiar, Cortar, Colar do macOS
    - Copiar, Cortar, Colar + Edição generalizada no iOS
- Melhores relatórios sobre permissões e conectividade na rede local
- Melhorias na estabilidade da conexão

## Em breve

- Atualmente em andamento
    - Certificar-se de que a entrada de texto no iOS não seja cortada abaixo do teclado (como está acontecendo agora)
    - Corrigir widgets do macOS
    - Atualizar iOS para a App Store
        - Esperar pelo acompanhamento do recurso
    - Melhorar os testes no iOS e macOS para testar se o sistema se reconecta e permanece conectado nos seguintes cenários
        - Após esperar muito tempo
        - Ao retornar do plano de fundo
        - Ao ligar a TV a partir do estado desligado
        - Ao se reconectar à internet
        - Ao trocar de dispositivos

- Próximo: Adicione um temporizador de silencio de +30 segundos com contagem regressiva
    - Pressione silenciar para silenciar por +30 segundos
    - Clique novamente para desativar o silêncio e cancelar
    - Mostre um indicador abaixo da linha do botão de silêncio
        - A barra de progresso possui um indicador de progresso linear
        - A barra de progresso possui dois botões: +30 segundos, cancelar
        - Mostrar abaixo do painel principal do botão para que fique perto do silêncio
    - Tornar o +30 configurável para opções de silêncio de 30, 15, 60 segundos

- Futuro: Forneça uma visualização minimalista opcional no iOS que reproduza de perto a visualização do controle remoto da Siri
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Suporte para gestos visionos também...

## Ideias gerais para o futuro

- Escreva um post no blog sobre o bot do Discord e aponte para a minha MessageView
    - Tornar a messageView mais autossuficiente
- Escreva um post no blog sobre a auto-tradução e a lógica em torno disso
- Escreva um post no blog sobre NWConnection vs URLSession para websockets
- Escreva um post no blog sobre atalhos de teclado personalizados
- Escreva um post no blog sobre a API ECP Textedit
- Escreva um post no blog sobre os widgets do centro de controle

- Crie um ícone personalizado para a barra de menus

- Como fazer texto em voz ou comandos de voz gerais?
    - Preciso fazer engenharia reversa no protocolo udp do controle remoto de voz roku
    - Ou preciso adicionar um texto personalizado para fala com o mecanismo de botão remoto?

- Automatizar a captura de capturas de tela

    - Use UITests para obter capturas de tela reais para todos os tamanhos e localidades de dispositivos
    - Use o AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obter as capturas de tela nos quadros
    - Ou algo mais
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/templates/s/iphone/

- Experimente mais truques de teclado para iPad
    - GCKeyboard para um
    - FocusEnvironment para 2
    - Certifique-se de que qualquer solução usada para iOS não interrompa a entrada de texto em mensagens/entrada de teclado

- Testes de interface do usuário
    - Teste quando um dispositivo é adicionado que ele apareça no seletor de dispositivo e seja selecionado pelo Roam
    - Teste que o usuário pode navegar para configurações -> dispositivos
    - Teste que o usuário pode navegar para configurações -> mensagens
    - Teste que o usuário pode navegar para configurações -> sobre
    - Teste que o usuário pode editar/excluir dispositivos
    - Teste que o usuário pode clicar nos botões uma vez que os dispositivos são adicionados
    - Teste que o usuário vê o banner de nenhum dispositivo quando ele aparece
    - Teste que o usuário vê os links de aplicativos
    - Consulte o modelo de teste do swiftdat para contêineres de modelo
    - Consulte aqui https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para configurar os testes

## Correções de bugs

- Descobrir se o laço de chamadas para `nextPacket` faz sentido.
    - Em vez de fazer um loop a cada 10ms e esperar que o tempo esteja correto, deveria estar fazendo um loop nos pacotes recebidos e tentando agendá-los no horário do host `10ms * globalSequenceNumber + startHostTime` e sampleTime para `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    - Então eu posso mudar de um loop `for await` sobre o relógio para um loop `while !Task.isCancelled` com um `Task.sleep` nele.
    - Ok, então precisamos fazer um loop a cada 10 ms e tentar retirar o último pacote e então agendá-lo naquele momento
    - Sempre que fazemos uma sincronização de áudio
        - Temos lastRenderTime + um pacote de sincronização
        - Avalie o número do pacote que deveríamos estar enviando + o tempo de sincronização
            - Render Time + adicional

## Melhorar as mensagens do usuário em torno da gestão de informações/status/capacidades

- Ao ligar o dispositivo com WOL e não se conectar depois de 5 segundos, ou ao ligar o dispositivo e falhar imediatamente, mostre uma mensagem de aviso abaixo da mensagem wifi
    - “Não conseguimos acordar o seu Roku” (Saiba mais) (Não mostrar novamente para este dispositivo), (X)
    - Saiba mais mostra algumas razões pelas quais isso pode acontecer
        - Você não está conectado à mesma rede (Mostrar o último nome da rede do dispositivo. Pergunte ao usuário se ele está conectado a esta rede)
        - Seu dispositivo está em sono profundo (não foi desligado recentemente) e não pode ser acordado
            - Seu dispositivo não suporta WWOL e está conectado ao wifi
            - Seu dispositivo não suporta WWOL ou WOL
        - Sua rede não está configurada de uma forma que nos permita enviar comandos de despertar para o dispositivo
- Ao clicar em um botão desativado, mostrar notificação indicando porque está desativado
    - Mostrar um indicador de informações no botão para indicar que informações podem ser recebidas quando ele é clicado?
    - Modo de fones de ouvido desabilitado -> porque o dispositivo não suporta o modo de fones de ouvido para este aplicativo
    - Controle de volume desabilitado -> porque o áudio está sendo transmitido por HDMI que não suporta controles de volume?
- Ao fazer a varredura ativa por dispositivos e nenhum novo é encontrado, mostra uma mensagem de aviso abaixo da lista de dispositivos
    - “Não conseguimos acordar o seu Roku” (Descubra o motivo), (X)
    - Saiba mais mostra um popup com algumas razões para isso estar acontecendo
        - Certifique-se de que seu dispositivo está ligado e conectado à mesma rede wifi que seu aplicativo. Se isso ainda não funcionar, tente adicionar o dispositivo manualmente.
        - Link https://roam.msd3.io/manually-add-tv.md e https://support.roku.com/article/115001480188 para mais solução de problemas ou chat
- Adicione uma medalha para supportsWakeOnWLAN e supportsMute

## Para atualizar ao abandonar o suporte para iOS 17/macOS 14 (fevereiro de 2026)

- Vá ao redor e remova as tags @available(iOS 18)
- Use preview traits para injetar dados de amostra nas pré-visualizações
- SwiftData
    - Use a nova macro #Index para modelos
    - Use a nova macro #Unique para modelos
    - Use a deleção em lote
- TipKit
    - Use CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698