---
hide_table_of_contents: true
---

# Trabalho mais recente no Roam

# Próximas atualizações do Roam

- Adicionado widgets de controle: Play, Silenciar, Alterar Volume e Selecionar no Control center!

## Mapa de Projeto

- Atualizar o manuseio do teclado para suportar ecp-textedit em `KeyboardEntry`
    - Mostrar teclado quando o textedit é aberto
    - Esconder teclado quando textedit é fechado
    - Garantir que colar + selecionar/excluir no campo textedit funcione conforme esperado
    - Use o campo de texto modificado atualmente, se ecp-textedit não for suportado, use o campo de texto padrão se for
    - No macOS, suporte ao colar com cmdP, copiar/cortar com cmdX + cmdC
    - Se o ecp-textedit não for suportado, volte para o comportamento atual de enviar teclas
    - No macOS, mostre um campo de texto na parte inferior quando o textedit estiver ativado
    - No macOS, permita cmd+v e cmd+c e cmd+x para copiar e colar do/para o buffer

- Adicionar temporizador de silenciamento de +30 segundos com contagem regressiva
    - Segure o botão de silenciar para silenciá-lo por +30 segundos
    - Clique novamente para desativar o silêncio e cancelá-lo
    - Mostre um indicador abaixo da linha do botão de silêncio 
        - A barra de progresso tem um indicador de progresso linear
        - A barra de progresso tem dois botões: +30 segundos, cancelar
        - Mostrar abaixo do painel principal do botão para que fique perto do botão de silêncio
    - Faça o +30 configurável para opções de silêncio de 30, 15, 60 segundos

- Fornecer uma visão minimalista opcional no iOS que replica de perto a visão do controle remoto da siri
    - https://support.apple.com/pt-pt/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Suporte para gestos visionOS também...

## Ideias Gerais Futuras

- Escrever um post no blog sobre o bot do discord e aponte para o meu MessageView
- Escrever um post no blog sobre a tradução automática e a lógica em torno disso

- Criar um ícone de barra de menu personalizado

- Como fazer voz-para-texto ou comandos de voz gerais?
    - Precisa reversar-engenheiro o protocolo udp do controle remoto de voz do roku
    - Ou precisa adicionar texto personalizado para fala com motor de botão remoto?

- Automatizar Captura de Captura de Ecrã

    - Use UITests para obter capturas de ecrã reais
    - Use AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obter as capturas de ecrã nos frames
    - Ou algo mais
        - https://www.figma.com/community/file/886620275115089774
        - https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        - https://www.canva.com/templates/s/iphone/

- Testar mais hacks de teclado
    - GCKeyboard para um
    - FocusEnvironment para 2
    - Certifique-se de que qualquer solução usada para o iOS não interrompa a entrada de texto nas mensagens/entrada de teclado

- Adicionar algum rastreamento de evento no que os usuários realmente estão fazendo em seus dispositivos (conectar-se ao firebase analytics talvez?)
    - Rastrear quem está usando a visualização minimalista, quais ações eles estão fazendo, etc...

## Correções de Bugs

- Descubra se o loop das chamadas para `nextPacket` faz sentido.
    - Em vez de fazer um loop a cada 10 ms e esperar que o tempo esteja correto, devo estar fazendo um loop sobre os pacotes recebidos e tentando agendá-los no tempo do host `10ms * globalSequenceNumber + startHostTime` e sampleTime para `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    - Então posso mudar de um loop `for await` sobre o relógio para um loop `while !Task.isCancelled` com um `Task.sleep` nele.
    - Okay, então precisamos fazer um loop a cada 10 ms e tentar retirar o último pacote e, em seguida, agendá-lo naquele momento
    - Sempre que fizermos uma sincronização de áudio
        - Temos lastRenderTime + um pacote de sincronização
        - Estimar o número do pacote que deveríamos estar enviando + o tempo de sincronização
            - Render Time + adicional

## Melhorar Testes

- Testes de Interface do Usuário
    - Testar quando o dispositivo é adicionado que ele aparece no seletor de dispositivo e é selecionado pelo roam
    - Testar que o usuário possa navegar para configurações -> dispositivos
    - Testar que o usuário pode navegar para configurações -> mensagens
    - Testar que o usuário pode navegar para configurações -> sobre
    - Testar que o usuário pode editar/excluir dispositivos
    - Testar que o usuário pode clicar em botões uma vez que os dispositivos são adicionados
    - Testar que o usuário vê a faixa para nenhum dispositivo quando ela aparece
    - Testar que o usuário vê applinks
    - Consulte swiftdat testingmodelcontainer para modelcontainers
    - Consulte aqui https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para saber como configurar testes

## App Clip

- AppClip
    - Adicionar um botão "obterUmLinkCompartilhávelParaEsteDispositivo" em configurações -> dispositivo
        - Pré-gerar todos os 1.1M códigos de clip de app e codificar locais de anel (0.5GB)
        - Faça um botão para "Obter um link compartilhável para o dispositivo!" com uma visualização de imagem no código do clip de app (cor roam)
        - Baixe o código + link e converta para PNG no dispositivo quando um local do dispositivo for alterado
        - Tenha o código para abrir o dispositivo como um link compartilhado para uma imagem (com pré-visualização!)
    - Faça também o link do dispositivo real compartilhável

## Melhorar a comunicação do usuário em torno da gestão de informações/status

- Atualize a gestão de informações/status para lidar melhor com o estado volátil
    - Ao desconectar, selecionar, clicar no botão, mover para o primeiro plano, abra o aplicativo -> Reinicie o loop de reconexão se estiver desconectado
    - O loop de reconexão é para tentar exponencialmente retomar as conexões falhadas (0.5s, dobro, 10s de backoff)
    - Ao se conectar ao dispositivo, sempre desativar os avisos de rede
    - Ao tentar se conectar ao dispositivo, ou tentar ligar o dispositivo, mostrar o ícone de informação girando em vez de um ponto cinza
    - Ao ligar o dispositivo e ter sucesso, mostrar uma animação na transição de cinza -> girando -> verde
    - Ao ligar o dispositivo com WOL e não se conectar após 5 segundos, ou ao ligar o dispositivo e falhar imediatamente, mostre uma mensagem de aviso abaixo do wifi uma
        - “Não conseguimos acordar o seu Roku” (Descubra mais) (Não mostrar novamente para este dispositivo), (X)
        - Descubra mais mostra algumas razões por que isso pode acontecer
            - Você não está conectado à mesma rede (Mostre o último nome da rede do dispositivo. Pergunte ao usuário se ele está conectado a essa rede)
            - Seu dispositivo está em sono profundo (não foi desligado recentemente) e não pode ser acordado
                - Seu dispositivo não suporta WWOL e está conectado ao wifi
                - Seu dispositivo não suporta WWOL ou WOL
            - Sua rede não está configurada de uma forma que nos permite enviar comandos para acordar o dispositivo
    - Loop de reconexão = Exponencial Backing off Tentativa de reconectar para reconectar ECP
        - Reconectar ECP primeiro
        - Ouvir para notificar segundo
            - Lidar com +mudança de modo de energia, +abertura de textedit, +mudança de textedit, +fecho de textedit, +mudança de nome do dispositivo
            - Certifique-se de que conseguimos lidar com cada uma dessas solicitações e seu formato...
        - Refrescar estado do dispositivo terceiro
        - Refrescar query-textedit-state quarto
            - Atualizar estado do textedit
        - Refrescar ícones do dispositivo quinto
    - Em todas as mudanças após a reconexão (por meio de notificação ou qualquer coisa)
        - Atualizar dispositivo (armazenado) e DeviceState (volátil)
    - Após reconectar/desconectar, atualize o status online na visualização remota

## Melhorar a comunicação do usuário em torno das capacidades do dispositivo

- Atualizar a comunicação do usuário quando os erros podem ocorrer
    - Quando clicar em um botão desativado, abrir um popover para mostrar por que ele está desativado
        - Mostrar um indicador de informação no botão para indicar que informações podem ser recebidas quando ele é clicado?
        - Modo de Fones de ouvido desativado -> porque o dispositivo não suporta modo de fones de ouvido para este aplicativo
        - Controle de Volume desativado -> porque o áudio está sendo transmitido sobre HDMI que não suporta controles de volume?
    - Quando estiver verificando ativamente os dispositivos e nenhum novo for encontrado, mostre uma mensagem de aviso abaixo da lista de dispositivos
        - “Não conseguimos acordar o seu Roku” (Descubra porquê), (X)
        - Descubra mais mostra um popup com algumas razões por que isso pode estar acontecendo
            - Certifique-se de que seu dispositivo está ligado e conectado à mesma rede wifi que seu aplicativo. Se isso ainda não funcionar, tente adicionar o dispositivo manualmente.
            - Link https://roam.msd3.io/manually-add-tv.md and https://support.roku.com/article/115001480188 para mais solução de problemas ou chat
- Adicionar crachá para supportsWakeOnWLAN e supportsMute

## Notas de texto ECP

Comandos de Sessão de Teclado ECP (notas)

```
- {"solicitar":"solicitar-eventos","id-de-solicitação":"4","param-eventos":"+língua-mudou,+língua-mudando,+estado-do-reprodutor-de-mídia-mudou,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-mudou,+sincronização-completada,+modo-de-energia-mudou,+volume-mudou,+tvinput-ui-run,+tvinput-ui-exit,+tv-canal-mudou,+textedit-aberto,+textedit-mudou,+textedit-fechado,+textedit-fechado,+ecs-microfone-iniciar,+ecs-microfone-parar,+nome-do-disposivo-mudou,+localização-do-dispositivo-mudou,+configuração-de-áudio-mudou,+configurações-de-áudio-invalidadas"}
    - {"notifcar":"textedit-aberto","param-mascarado":"falso","param-max-comprimento":"75","param-seleção-fim":"0","param-seleção-início":"0","param-texto":"","param-textedit-id":"12","param-textedit-tipo":"completo","timestamp":"608939.003"}
- {"solicitar":"query-textedit-state","id-de-solicitação":"10"}
    - {"data-conteúdo":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","tipo-de-conteúdo":"application/json; charset=\"utf-8\"","resposta":"query-textedit-state","id-de-resposta":"10","status":"200","status-mensagem":"OK"}
- {"param-texto":"h","param-textedit-id":"12","solicitar":"set-textedit-text","id-de-solicitação":"20"}
    - {"resposta":"set-textedit-text","id-de-resposta":"29","status":"200","status-mensagem":"OK"}
```

## Para atualizar quando terminar o suporte ao iOS 17/macOS 14 (Feb 2026)

- Vá e remova as tags @available (iOS 18)
- Use traços de pré-visualização para injetar dados amostrais em pré-visualizações
    - Como fazer isso com o iOS 17 ainda sendo um fator?
    - Como usar @Previewable em prévias com o iOS 17 ainda um fator??
- SwiftData
    - Use a nova macro #Index para modelos
    - Use a nova macro #Unique para modelos
    - Use a exclusão em lote
- TipKit
    - Use CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698