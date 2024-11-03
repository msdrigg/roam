---
hide_table_of_contents: true
---

# Trabalho mais recente no roam

# Atualizações futuras no Roam

- Adicionado widgets de controle: Reproduzir, Silenciar, Alterar Volume e Selecionar no Centro de controle!

## Roadmap

-   Atualizar o manuseio do teclado para suportar ecp-textedit no `KeyboardEntry`
    -   Mostrar teclado quando o textedit é aberto
    -   Esconder teclado quando textedit fechado
    -   Garantir que colar + selecionar/excluir no campo textedit funcione como esperado
    -   Use o campo de texto modificado atual se o ecp-textedit não for suportado, use o campo de texto padrão se for 
    -   No macOS, suporte colar com cmdP, copiar/recortar com cmdX + cmdC
    -   Se o ecp-textedit não for suportado, recorrer ao comportamento atual de enviar teclas
    -   No macOS, mostre um campo de texto na parte inferior quando o textedit estiver ativado
    -   No macOS, permita cmd+v e cmd+c e cmd+x para copiar e colar do/para o buffer

-   Adicionar um temporizador de silêncio de +30 segundos com contagem regressiva
    -   Mantenha pressionado para silenciar por +30 segundos
    -   Clique novamente para desativar e cancelá-lo
    -   Mostre um indicador abaixo da linha do botão mute
        -   A barra de progresso tem um indicador de progresso linear
        -   A barra de progresso tem dois botões: +30 segundos, cancelar
        -   Mostrar abaixo do painel de botões principal para que fique próximo ao botão mute
    -   Torne o +30 configurável para opções de mudo de 30, 15, 60 segundos

-   Forneça uma visão minimalista opcional no iOS que replica de perto a visualização do controle remoto siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Suporte para gestos visionos também...

## Ideias Gerais Futuras

-   Escreva um post no blog sobre o bot discord e aponte para meu MessageView
-   Escreva um post no blog sobre a auto-tradução e a lógica ao redor disso

-   Faça um ícone de barra de menu personalizado

-   Como fazer voz para texto ou comandos de voz gerais?
    - Preciso reverter a engenharia do protocolo udp do controle remoto de voz roku
    - Ou preciso adicionar texto personalizado para fala com o motor de botão remoto?
    
-   Automatizar a captura de screenshots

    -   Use testes de UI para obter screenshots reais
    -   Use AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obter as screenshots nos quadros
    -   Ou outra coisa
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Testar mais hacks de teclado
    -   GCKeyboard para um
    -   FocusEnvironment para 2
    -   Garantir que qualquer solução utilizada para o iOS não danifique a entrada de texto nas mensagens/entrada de teclado

-   Adicionar algum rastreamento de evento sobre quais ações os usuários estão realmente fazendo em seus dispositivos (conectar ao firebase analytics talvez?)
    -   Acompanhe quem está usando a exibição minimalista, quais ações estão fazendo, etc...

## Correções de bugs

-   Descobrir se o loop de chamadas para `nextPacket` faz sentido.
    -   Em vez de fazer looping a cada 10ms e esperar que o tempo esteja correto, devo estar fazendo looping nas pacotes recebidos e tentando agendá-los no horário do host `10ms * globalSequenceNumber + startHostTime` e sampleTime para `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Então, posso mudar de um loop `for await` pelo relógio para um loop `while !Task.isCancelled` com um `Task.sleep` nele.
    -   Ok, então precisamos fazer loop a cada 10 ms e tentar tirar o último pacote e, então, programá-lo naquele momento
    -   Sempre que fazemos uma sincronização de áudio
        -   Temos lastRenderTime + um pacote de sincronização
        -   Estimamos o número do pacote que deveríamos estar enviando em + o tempo de sincronização
            -   Tempo de renderização + adicional

## Melhorar os testes

-   Testes de UI
    -   Testar quando o dispositivo é adicionado, que ele apareça no seletor de dispositivo e seja selecionado pelo roam
    -   Testar que o usuário pode navegar para configurações -> dispositivos
    -   Testar que o usuário pode navegar para configurações -> mensagens
    -   Testar que o usuário pode navegar para configurações -> sobre
    -   Testar que o usuário pode editar/excluir dispositivos
    -   Testar que o usuário pode clicar nos botões uma vez que os dispositivos são adicionados
    -   Testar que o usuário vê o banner de nenhum dispositivo quando ele aparece
    -   Testar que o usuário vê applinks
    -   Consulte o swiftdat testingmodelcontainer para modelcontainers
    -   Consulte aqui https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para saber como configurar testes

## App Clip

-   AppClip
    -   Adicione um botão "getAShareableLinkToThisDevice" em configurações -> dispositivo
        -   Pré-gerar todos os 1,1M códigos de clip de aplicativo e codificar locais de anel (0.5GB)
        -   Faça um botão para "Obtenha um link compartilhável para o dispositivo!" com uma imagem visualizando o código do clip do aplicativo (cor roam)
        -   Baixe o código + link e converta para PNG no dispositivo quando a localização de um dispositivo for alterada
        -   Faça o código abrir o dispositivo como um link compartilhado para uma imagem (com pré-visualização!)
    -   Também faça o link do dispositivo real compartilhável

## Melhore a comunicação do usuário sobre gestão de status/informação

-   Atualize a gestão de status/informação para lidar melhor com o estado volátil
    -   Na desconexão, seleção, clique em botão, mova para o primeiro plano, aplicativo aberto -> Reinicie o loop de reconexão se desconectado
    -   O loop de reconexão é para tentar novamente conexões falhas com backoff exponencial (0.5s, dobrar, 10s backoff)
    -   Quando conectado ao dispositivo, sempre desabilite os avisos de rede
    -   Ao tentar se conectar ao dispositivo, ou tentar ligar o dispositivo, mostre o ícone de informação girando em vez do ponto cinza
    -   Ao ligar o dispositivo e ter sucesso, mostre uma animação na transição de cinza -> girando -> verde
    -   Ao ligar o dispositivo com WOL e não conectar após 5 segundos, ou ao ligar o dispositivo e falhar imediatamente, mostre uma mensagem de aviso abaixo da que está do wifi
        -   “Não conseguimos acordar o seu Roku” (Saiba mais) (Não mostrar novamente para este dispositivo), (X)
        -   Saiba mais mostra algumas razões possíveis
            -   Você não está conectado à mesma rede (Mostre o último nome da rede do dispositivo. Pergunte se o usuário está conectado a esta rede)
            -   Seu dispositivo está em sono profundo (não foi desligado recentemente) e não pode ser despertado
                -   Seu dispositivo não suporta WWOL e está conectado ao wifi
                -   Seu dispositivo não suporta WWOL ou WOL
            -   Sua rede não está configurada de uma forma que nos permita enviar comandos de despertar para o dispositivo
    -   Loop de reconexão = Tentativa exponencial de se reconectar ao ECP
        -   Reconecte primeiro o ECP
        -   Ouça a notificação em segundo lugar
            -   Lide com +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   Certifique-se de que podemos lidar com cada um desses pedidos e seu formato...
        -   Atualize o estado do dispositivo em terceiro lugar
        -   Atualize o estado do textedit da consulta em quarto lugar
            -   Atualize o estado do textedit
        -   Atualize os ícones do dispositivo em quinto lugar
    -   Em todas as mudanças após a reconexão (através de notificar ou qualquer coisa)
        -   Atualize o dispositivo (armazenado) e o estado do dispositivo (volátil)
    -   Após reconectar/desconectar, atualize o status online na visualização remota

## Melhorar a comunicação do usuário sobre as capacidades do dispositivo

-   Atualize a mensagem do usuário quando erros podem ocorrer
    -   Ao clicar em um botão desativado, abra um pop-up para mostrar por que ele está desativado
        -   Mostre um indicador de informação no botão para indicar que informações podem ser recebidas quando ele é clicado?
        -   Modo de fones de ouvido desativado -> porque o dispositivo não suporta o modo de fones de ouvido para este aplicativo
        -   Controle de volume desativado -> porque o áudio está sendo transmitido via HDMI, o que não suporta controles de volume?
    -   Ao escanear ativamente por dispositivos e não encontrar novos, mostre uma mensagem de aviso abaixo da lista de dispositivos
        -   “Não conseguimos acordar o seu Roku” (Descubra o motivo), (X)
        -   Saiba mais mostra um pop-up com algumas razões para isso estar acontecendo
            -   Certifique-se de que seu dispositivo esteja ligado e conectado à mesma rede wifi de seu aplicativo. Se isso ainda não funcionar, tente adicionar o dispositivo manualmente.
            -   Link https://roam.msd3.io/manually-add-tv.md e https://support.roku.com/article/115001480188 para mais solução de problemas ou bate-papo
-   Adicionar crachá para supportsWakeOnWLAN e supportsMute

## Notas ECP textedit

Comandos da Sessão ECP do Teclado (notas)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Atualizar quando parar de dar suporte ao iOS 17/macOS 14 (Fevereiro de 2026)

-   Percorra e remova as tags @available(iOS 18)
-   Use as características da visualização para inserir dados de amostra em visualizações
    -   Como fazer isso com iOS 17 ainda sendo um fator?
    -   Como usar @Previewable em pré-visualizações com iOS 17 ainda sendo um fator??
-   SwiftData
    -   Use o novo macro #Index para modelos
    -   Use o novo macro #Unique para modelos
    -   Use exclusão em lote
-   TipKit
    -   Use CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
