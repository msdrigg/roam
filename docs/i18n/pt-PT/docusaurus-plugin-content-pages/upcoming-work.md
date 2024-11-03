---
hide_table_of_contents: true
---

# Trabalhos mais recentes do Roam

# Próximas Atualizações do Roam

## Melhorias Gerais

-   Atualizar as traduções para garantir que todas estejam a 100%
-   Documentar o bot de suporte no discord e possivelmente duplicá-lo numa biblioteca
-   Criar ícone personalizado na barra de menu

-   Como fazer comando de voz para texto ou comando de voz em geral?
    - Necessário reengenharia o udp protocol do comando de voz do roku
    - Ou seria necessário adicionar um texto personalizado para voz com mecanismo de botão remoto?

-   Adicionar temporizador de silêncio de +30 segundos com contagem decrescente
    -   Pressione e segure silêncio para silenciar por +30 segundos
    -   Clique novamente para cancelar silêncio
    -   Mostrar uma notificação na barra superior
        -   A barra de progresso tem um indicador de progresso linear
        -   A barra de progresso tem dois botões: +30 segundos, cancelar
        -   Mostrar abaixo do painel de botão principal para que esteja perto do silêncio
    -   Fazer o +30 configurável para 30, 15, 60 opções de silêncio em segundos

-   Automatizar a Captura de Capturas de Ecrã

    -   Utilizar UITests para obter capturas de ecrã reais
    -   Utilizar AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w para obter as capturas de ecrã nas molduras
    -   Ou algo mais
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Teste mais hacks de teclado
    -   GCKeyboard para um
    -   FocusEnvironment para 2
    -   Certifique-se de que qualquer solução usada para iOS não interrompe a entrada de texto em mensagens / entrada de teclado
    
-   Implementar iOS 18 AppIntents
    -   Adicionar app intents ao centro de controle
        -   Utilizar a alternância para silenciar/desligar e ligar/desligar
        -   Utilizar botões para tudo o resto
        -   Utilizar a tonalidade correta de roxo
        -   Tornar configurável assim como os widgets
        -   Fazer funcionar com a dica de ação
    -   Permitir que a siri/foco veja melhor as coisas no meu aplicativo de alguma forma?
        -   Adicionar links universais para os dispositivos para que a siri possa vinculá-los?
        -   Certificar-se de que a pesquisa semântica funciona
        -   Implementar transferível através de string / codificável para minhas entidades de aplicativo
            -   ProxyRepresentation
            -   CodableRepresentation
-   Fornecer uma vista minimalista opcional no iOS que replica de perto a vista do controle remoto da siri
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Suportar também os gestos visionos...
    -   É necessário construir a api textedit primeiro
-   Adicionar algum rastreamento de eventos sobre que ações os usuários estão realmente fazendo em seus dispositivos (conectar ao firebase analytics talvez?)
    -   Rastrear quem está usando a vista minimalista, quais ações estão fazendo, etc...

## Correção de Erros

-   Determinar se o loop de chamadas para `nextPacket` faz sentido.
    -   Em vez de fazer um loop a cada 10ms e esperar que o tempo esteja correto, devo estar fazer um loop nos pacotes recebidos e tentar agendá-los no momento do host `10ms * globalSequenceNumber + startHostTime` e sampleTime to `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Então eu posso mudar de um loop `for await` sobre o relógio para um loop `while !Task.isCancelled` com um `Task.sleep` nele.
    -   Certo, então precisamos fazer um loop a cada 10 ms e tentar retirar o último pacote e depois agendá-lo naquele tempo
    -   Sempre que fizermos uma sincronização de áudio
        -   Temos lastRenderTime + um pacote de sincronização
        -   Estimar o número do pacote que deveríamos estar enviando em + o tempo de sincronização
            -   Render Time + extra

## Melhorar Testes

-   Testes de Interface do Utilizador
    -   Testar quando um dispositivo é adicionado se este aparece no seletor de dispositivos e é selecionado pelo roam
    -   Testar se o utilizador pode navegar para configurações -> dispositivos
    -   Testar se o utilizador pode navegar para configurações -> mensagens
    -   Testar se o utilizador pode navegar para configurações -> sobre
    -   Testar se o utilizador pode editar/excluir dispositivos
    -   Testar se o utilizador pode clicar nos botões uma vez que os dispositivos estão adicionados
    -   Testar se o usuário vê a faixa para nenhum dispositivo quando ela aparece
    -   Testar que o usuário vê applinks
    -   Consultar o swiftdat testingmodelcontainer para modelcontainers
    -   Consultar aqui https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad para como configurar testes

## App Clip

-   AppClip
    -   Adicionar um botão "obtenhaUmLinkParaPartilharEsteDispositivo" nas configurações -> dispositivo
        -   Pré-gerar todos os 1.1M códigos de app clip e codificar locais de anel (0.5GB)
        -   Criar um botão para "Obter um link compartilhável para o dispositivo!" com uma pré-visualização de imagem para o código do app clip (roam cor)
        -   Baixe o código + link e converta para PNG no dispositivo quando a localização do dispositivo for alterada
        -   Que o código abra o dispositivo como um link compartilhado para uma imagem (com pré-visualização!)
    -   Também tornar o link do dispositivo real partilhável

## Melhorar a comunicação com o usuário sobre a gestão de informações/status

-   Atualizar Informação/gestão de status para lidar melhor com o estado volátil
    -   Na desconexão, selecionar, clicar em botões, mover para o primeiro plano, abrir o aplicativo -> Reiniciar o loop de reconexão se desconectado
    -   O loop de reconexão serve para tentar retentativas de conexões falhadas de forma exponencial (0.5s, duplicar, 10s de espera)
    -   Quando conectado ao dispositivo, sempre desabilite os avisos de rede
    -   Ao tentar conectar-se ao dispositivo, ou tentando ligar o dispositivo, mostre um ícone de informação rodando em vez do ponto cinzento
    -   Ao ligar o dispositivo e ter sucesso, mostre uma animação na transição de cinzento -> rodando -> verde
    -   Ao ligar o dispositivo com WOL e não conectar após 5 segundos, ou ao ligar o dispositivo e falhar imediatamente, mostre uma mensagem de aviso sob a wifi
        -   “Não conseguimos acordar o seu Roku” (Descubra mais) (Não mostre novamente para este dispositivo), (X)
        -   Descubra mais mostra algumas razões pelas quais
            -   Você não está conectado à mesma rede (Mostrar o último nome da rede do dispositivo. Perguntar se o usuário está conectado a esta rede)
            -   Seu dispositivo está em sono profundo (não foi desligado recentemente) e não pode ser acordado
                -   Seu dispositivo não suporta WWOL e está conectado por wifi
                -   Seu dispositivo não suporta WWOL ou WOL
            -   Sua rede não está configurada de maneira a permitir que nós enviemos comandos de acordar para o dispositivo
    -   O loop de reconexão = Tentando em esperas exponenciais se reconectar ao ECP
        -   Reconectar ECP primeiro
        -   Ouvir notificações em segundo lugar
            -   Lidar com +power-mode-changed, +textedit-opened, +textedit-changed, +textedit-closed, +device-name-changed
            -   Certificar-se de que podemos lidar com cada um desses pedidos e seu formato…
        -   Atualizar o estado do dispositivo em terceiro lugar
        -   Atualizar query-textedit-state em quarto lugar
            -   Atualizar o estado de edição de texto
        -   Atualizar os ícones dos dispositivos por quinto
    -   Em todas as mudanças após a reconexão (através de notificação ou qualquer coisa)
        -   Atualizar Dispositivo (armazenado) e DeviceState (violatile)
    -   Após a reconexão / desconexão, atualizar o status online na visualização remota

## Melhorar a comunicação com o usuário sobre as capacidades do dispositivo

-   Atualizar comunicação com o usuário quando erros possam ocorrer
    -   Ao clicar num botão desativado, abrir uma janela pop-up para mostrar por que está desativado
        -   Mostrar um indicador de informação no botão para indicar que se pode obter informação ao clicar?
        -   Modo de fones de ouvido desativado -> porque o dispositivo não suporta o modo de fones de ouvido para este aplicativo
        -   Controle de volume desativado -> porque o áudio está sendo transmitido pelo HDMI, que não suporta regulagens de volume?
    -   Ao fazer a varredura ativa por dispositivos e nenhum novo é encontrado, mostre uma mensagem de aviso abaixo da lista de dispositivos
        -   "Não conseguimos acordar o seu Roku" (Descubra porquê), (X)
        -   Descubra mais mostra um pop-up com algumas razões pelas quais isso pode estar acontecendo
            -   Certifique-se de que o seu dispositivo está ligado e conectado à mesma rede wi-fi do seu aplicativo. Se ainda não funcionar, tente adicionar o dispositivo manualmente.
            -   Ligação https://roam.msd3.io/manually-add-tv.md e https://support.roku.com/article/115001480188 para mais solução de problemas ou bate-papo
-   Adicionar crachá para supportsWakeOnWLAN e supportsMute

## Suportar ecp textedit

-   Atualizar a manipulação do teclado para suportar ecp-textedit em `KeyboardEntry`
    -   Mostrar teclado quando o textedit está aberto
    -   Ocultar teclado quando o textedit estiver fechado
    -   Testar que colar + selecionar/excluir no campo textedit funciona como esperado
    -   Se o ecp-textedit for suportado, permita selecionar, excluir texto e mover o cursor. Apenas reenvie o texto cada vez que ele mudar se isso for suportado.
    -   Se ecp-textedit não for suportado, volte ao comportamento atual de envio de teclas
    -   No macOS, mostrar um indicador quando o textedit estiver ativado
    -   No macOS, permitir cmd+v e cmd+c e cmd+x para copiar colar de/para o buffer

Comandos de Sessão ECP do Teclado (notas)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## Para atualizar ao abandonar o suporte para iOS 17/macOS 15 (2025)

-   Utilizar traços de pré-visualização para inserir dados de amostra em pré-visualizações
    -   Como fazer isso com o iOS 17 ainda sendo um fator?
    -   Como utilizar o @Previewable em pré-visualizações com o iOS 17 ainda sendo um fator??
-   SwiftData
    -   Utilizar novo macro #Index para modelos
    -   Utilizar novo macro #Unique para modelos
    -   Utilizar a exclusão em lote
-   TipKit
    -   Utilizar CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
