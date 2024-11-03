---
hide_table_of_contents: true
---

# Mais recentes trabalhos no Roam

# Próximas atualizações do Roam

## Melhorias gerais

- Atualizar as traduções para garantir que todas estejam a 100%
- Documentar o bot de suporte do Discord e talvez duplicá-lo em uma biblioteca
- Fazer ícone personalizado na barra de menus

- Como fazer voz-para-texto ou comandos de voz em geral?
    - Precisa-se fazer engenharia reversa do protocolo udp do controle remoto por voz Roku
    - Ou precisa-se adicionar texto personalizado para fala com mecanismo de botão remoto?

- Adicionar temporizador de mudo de +30 segundos com contagem regressiva
    - Mante pressionado para silenciar por +30 segundos
    - Clique novamente para cancelar o mudo
    - Mostrar uma notificação na barra superior
        - A barra de progresso tem um indicador de progresso linear
        - A barra de progresso tem dois botões: +30 segundos, cancelar
        - Mostrar abaixo do painel de botão principal para que esteja perto do botão mudo
    - Tornar o +30 configurável para opções de mudo de 30, 15, 60 segundos

- Automatizar captura de captura de tela

    - Usar UITests para capturar screenshots reais
    - Usar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para capturar as screenshots em molduras
    - Ou outra coisa
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/templates/s/iphone/

- Teste mais hack de teclado
    - GCKeyboard para um
    - Ambiente de foco para dois
    - Garantir que qualquer solução usada para iOS não cause problemas ao escrever textos em mensagens/entrada de teclado
    
- Implementar iOS 18 AppIntents
    - Adicionar app intents ao centro de controle
        - Usar uma chave para ativar/desativar e ligar/desligar
        - Usar botões para tudo o mais
        - Usar a cor roxa correta
        - Tornar configurável assim como os widgets
        - Funcionar com dica de ação
    - Permitir que a Siri/Spotlight veja melhor as coisas no meu aplicativo de alguma forma?
        - Adicionar links universais aos dispositivos para que a Siri possa ligar para eles?
        - Certificar-se que a pesquisa semântica funciona
        - Implementar transferível por string/codificável para minhas entidades de aplicativos
            - Representação de proxy
            - Representação codificável
- Fornecer uma visualização minimalista opcional no iOS que replica de perto a visualização do controle remoto da Siri
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Suportar gestos do visionos também...
    - Necessário construir a API de edição de texto primeiro
- Adicionar algum rastreamento de eventos sobre quais ações os usuários estão realmente fazendo em seus dispositivos (conectar ao Google Analytics talvez?)
    - Rastrear quem está usando a visualização minimalista, quais ações estão fazendo, etc.

## Correção de bugs

- Descobrir se o loop de chamadas para `nextPacket` faz sentido.
    - Em vez de fazer loop a cada 10 ms e esperar que o tempo esteja correto, devo estar fazendo loop sobre pacotes recebidos e tentando agendá-los em `10ms * globalSequenceNumber + startHostTime` e sampleTime para `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    - Então posso mudar de um loop `for await` sobre o relógio para um loop `while !Task.isCancelled` com um `Task.sleep` nele.
    - Ok, então precisamos fazer loop a cada 10 ms e tentar puxar o último pacote e então agendá-lo naquele horário
    - Sempre que fazemos uma sincronização de áudio
        - Nós temos lastRenderTime + um pacote de sincronização
        - Estimativa do número do pacote que deveríamos estar enviando em + o tempo de sincronização
            - Render Time + adicional

## Melhorar testes

- UI Tests
    - Testar quando o dispositivo é adicionado que ele aparece no dispositivo selecionado por roam
    - Testar que o usuário pode navegar para configurações -> dispositivos
    - Testar que o usuário pode navegar para configurações -> mensagens
    - Testar que o usuário pode navegar para configurações -> sobre
    - Testar que o usuário pode editar/excluir dispositivos
    - Testar que o usuário pode clicar em botões uma vez que os dispositivos são adicionados
    - Testar que o usuário vê o banner para nenhum dispositivo quando ele aparece
    - Testar que o usuário vê applinks
    - Consulte swiftdat testingmodelcontainer para modelcontainers
    - Consulte aqui https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para aprender a configurar testes

## App Clip

- AppClip
    - Adicionar um botão "obtenha um link compartilhável para este dispositivo" em configurações -> dispositivo
        - Pré-gerar todos os códigos de 1.1M app clip e codificar locais de anel (0.5GB)
        - Faça um botão para "Obter um link compartilhável ao dispositivo!" com uma pré-visualização de imagem para o código do app clip (cor roam)
        - Fazer download do código + link e converter para PNG no dispositivo quando a localização do dispositivo é alterada
        - Tenha o código aberto como um link compartilhado para uma imagem (com pré-visualização!)
    - Também faça o link do dispositivo real compartilhável

## Melhorar mensagens ao usuário sobre gerenciamento de informações/status 

- Atualizar o gerenciamento de informações/status para lidar melhor com o estado volátil
    - Na desconexão, seleção ou clique no botão, mover para primeiro plano, aplicativo aberto -> Reiniciar loop de reconexão se desconectado
    - O loop de reconexão é para tentar novamente as conexões que falharam com uma decrescente exponencialmente (0.5s, dobrar, 10s de decréscimo)
    - Quando conectado ao dispositivo, sempre desativar os avisos de rede
    - Ao tentar se conectar ao dispositivo, ou tentar ligar o dispositivo, mostre um ícone de informação girando em vez do ponto cinza
    - Ao ligar o dispositivo e ter sucesso, mostre uma animação na transição de cinza -> girando -> verde
    - Ao ligar o dispositivo com WOL e não conectar depois de 5 segundos, ou quando ligar o dispositivo e falhar imediatamente, mostre uma mensagem de aviso abaixo do wifi
        - “Não podemos acordar seu Roku” (Saiba mais) (Não mostre novamente para este dispositivo), (X)
        - Saiba mais mostra algumas razões porque
            - Você não está conectado à mesma rede (Mostra o último nome de rede do dispositivo. Pergunte se o usuário está conectado a esta rede)
            - Seu dispositivo está em sono profundo (não foi desativado recentemente) e não pode ser acordado
                - Seu dispositivo não suporta WWOL e está conectado ao wifi
                - Seu dispositivo não suporta WWOL ou WOL
            - Sua rede não está configurada de forma a nos permitir enviar comandos de despertar para o dispositivo
    - Loop de reconexão = Tenta novamente de forma decrescente exponencialmente para reconectar ECP
        - Reconectar ECP primeiro
        - Ouvir notificação em segundo lugar
            - Lidar com +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            - Certifique-se de que podemos lidar com cada uma dessas solicitações e seus formatos...
        - Atualizar o status do dispositivo terceiro
        - Consulta-textedit-state quarto
            - Atualizar estado do textedit
        - Atualizar ícones do dispositivo quinto
    - Em todas as mudanças depois de reconectar (através de notificação ou qualquer coisa)
        - Atualizar o dispositivo (armazenado) e o estado do dispositivo (voilatile)
    - Após reconectar/desconectar, atualizar o status online na visualização remota

## Melhorar mensagens ao usuário sobre as capacidades do dispositivo 

- Atualizar mensagens ao usuário quando podem ocorrer erros
    - Ao clicar em um botão desativado, abrir um pop-up para mostrar por que está desativado
        - Mostrar um indicador de informações no botão para indicar que as informações podem ser recebidas quando é clicado?
        - Modo de fones de ouvido desativado -> porque o dispositivo não suporta o modo de fones de ouvido neste aplicativo
        - Controle de volume desativado -> porque o áudio está sendo transmitido via HDMI, que não suporta controles de volume?
    - Quando estiver procurando ativamente por dispositivos e não encontrar nenhum novo, mostrar uma mensagem de aviso abaixo da lista de dispositivos
        - “Não conseguimos acordar seu Roku” (Descubra o porquê), (X)
        - Descubra mais mostra um pop-up com algumas razões por que isso pode estar acontecendo
            - Certifique-se de que seu dispositivo está ligado e conectado à mesma rede wifi que seu aplicativo. Se ainda não funcionar, tente adicionar o dispositivo manualmente.
            - Link https://roam.msd3.io/manually-add-tv.md and https://support.roku.com/article/115001480188 para mais suporte ou chat
- Adicionar insígnia para suportaWakeOnWLAN e suportaMute

## Suporte a ecp textedit

- Atualizar o manuseio do teclado para suportar o ecp-textedit no `KeyboardEntry`
    - Mostrar o teclado quando o textedit for aberto
    - Esconder o teclado quando o textedit for fechado
    - Testar que colar + selecionar/excluir no campo de textedit funciona conforme esperado
    - Se o ecp-textedit for suportado, permitir seleção, exclusão de texto e movimentação do cursor. Basta reenviar o texto cada vez que ele for alterado se isso for suportado.
    - Se o ecp-textedit não for suportado, voltar ao comportamento atual de enviar teclas
    - No macOS, mostrar um indicador quando o textedit estiver habilitado 
    - No macOS, permitir cmd+v e cmd+c e cmd + x para copiar e colar do/para o buffer

Comandos da sessão ECP do teclado (notas)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Para atualizar quando descontinuar o suporte para iOS 17/macOS 15 (2025)

- Use características de pré-visualização para injetar dados de amostra em pré-visualizações
    - Como fazer isso com iOS 17 ainda sendo um fator?
    - Como usar @Previewable em pré-visualizações com iOS 17 ainda sendo um fator??
- SwiftData
    - Use novo macro #Index para modelos
    - Use novo macro #Unique para modelos
    - Use exclusão em lote
- TipKit
    - Use CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
