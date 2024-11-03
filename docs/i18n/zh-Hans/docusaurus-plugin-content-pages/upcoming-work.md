---
hide_table_of_contents: true
---

# 最近的漫游工作

# 即将推出的漫游更新

## 一般性改进

-   更新翻译以确保所有翻译都达到100%
-   记录 discord 支持机器人并可能将其复制到一个库中
-   自定义菜单栏图标

-   如何进行语音到文本或一般的语音命令？
    - 需要反向工程化 roku 语音遥控器 udp 协议
    - 或需要添加带有远程按钮引擎的自定义文本到语音？

-   添加 30 秒静音计时器并倒计时
    -   长按静音键以静音 30 秒
    -   再次点击以取消静音
    -   显示一个顶部栏通知
        -   进度条有一个线性进度指示器
        -   进度条有两个按钮：+30 秒，取消
        -   显示在主按钮面板下方，因此离静音键很近
    -   将 +30 可配置为 30，15，60秒静音选项

-   自动截屏捕获

    -   使用 UITests 获取实际截图
    -   将截图存储在 AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w 上
    -   或者其他
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   测试更多键盘攻击
    -   用一个 GCKeyboard
    -   用于 2 的 FocusEnvironment
    -   确保在 iOS 中使用的任何解决方案不会破坏消息/键盘入口中的文本输入
    
-   实现 iOS 18 AppIntents
    -   添加控制中心应用意图
        -   使用切换开关进行静音/取消静音和开/关电源
        -   其他操作使用按钮
        -   使用正确的紫色调色
        -   使其可配置，就像小部件一样
        -   随着操作提示一起使用
    -   让 Siri/Spotlight 更好地看到我应用中的东西？
        -   将通用链接添加到设备，以便 Siri 可以链接到它们？
        -   确保语义搜索有效
        -   为我的应用实体实现可通过字符串/代码转移
            -   ProxyRepresentation
            -   CodableRepresentation
-   在 iOS 上提供一个可选的精简视图，紧密地复制 Siri 远程视图
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   支持 VisionOS 手势。。。
    -   首先需要构建 textedit api
-   添加一些事件追踪，了解用户在其设备上究竟做了哪些操作（可能连接到 Firebase 分析？）
    -   追踪谁在使用精简视图，他们做了哪些操作，等等...

## Bug修复

-   弄清楚调用 `nextPacket` 的循环是否有意义。
    -   而非每 10 毫秒循环一次并希望时机正确，我应该遍历接收到的数据包并试图在主机时间 `10ms * globalSequenceNumber + startHostTime` 和 sampleTime 到 `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime` 它们。
    -   那么我可以从对时钟的 `for await` 循环切换到带有 `Task.sleep` 的 `while !Task.isCancelled` 循环。
    -   好吧，所以我们需要每隔 10 毫秒循环一次，试图拉取最后一个数据包，然后在那时安排它
    -   无论我们做音频同步
        -   我们有 lastRenderTime + 一个同步数据包
        -   估计我们应该在 + 同步时间发送出去的数据包序号
            -   渲染时间 + 附加内容

## 改善测试

-   UI 测试
    -   测试当设备添加时，它是否出现在设备选择器中，并由漫游选中
    -   测试用户是否可以导航到设置 -> 设备
    -   测试用户是否可以导航到设置 -> 消息
    -   测试用户是否可以导航到设置 -> 关于
    -   测试用户是否可以编辑/删除设备
    -   测试用户是否可以点击按钮一次设备被添加
    -   测试用户在没有设备显示时是否看到横幅
    -   测试用户是否看到应用链接
    -   参考 swiftdat testingmodelcontainer 进行模型容器
    -   针对如何设置测试，参考这里 https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad 

## App Clip

-   AppClip
    -   在设置 -> 设备上添加一个 "getAShareableLinkToThisDevice" 按钮
        -   预生成所有 1.1M 的应用剪辑代码并编码环位置（0.5GB）
        -   制作一个 "获取到此设备的可共享链接！" 的按钮，包含应用剪辑代码的图片预览（漫游颜色）
        -   当设备位置改变时，下载该代码 + 链接并在设备上转换为 PNG
        -   让该代码以共享链接的形式打开设备（带预览！）
    -   也使实际设备链接可共享

## 改善围绕信息/状态管理的用户消息

-   更新信息/状态管理以更好地处理不稳定状态
    -   在断开连接、选择、点击按钮、移到前台、打开应用程序时 -> 如果断开连接，则重启重新连接循环
    -   重新连接循环是指指数级回退重试失败的连接（0.5s，加倍，10s 回退）
    -   连接到设备时，始终禁用网络警告
    -   尝试连接到设备，或尝试打开设备时，显示旋转信息图标，而非灰色点
    -   打开设备并成功时，显示从灰色 -> 旋转 -> 绿色的过渡动画
    -   使用网络唤醒打开设备后 5 秒钟内没有连接，或者打开设备并立即失败，在 wifi 通知下方显示警告消息
        -   “我们无法唤醒您的 Roku”（了解更多）（不再针对此设备显示）（X）
        -   了解更多显示一些可能的原因
            -   您没有连接到相同的网络（显示上次设备网络名称。询问用户是否连接到此网络）
            -   您的设备处于深度休眠状态（没有最近断电）无法被唤醒
                -   您的设备不支持 WWOL 并且已连接到 wifi
                -   您的设备不支持 WWOL 或 WOL
            -   您的网络没有以使我们能够向设备发送唤醒命令的方式设置
   -   重新连接循环 = 指数级回退尝试重新连接 ECP
        -   先重新连接 ECP
        -   第二步监听通知
            -   处理 +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   确保我们可以处理这些请求和它们的格式...
        -   第三步刷新设备状态
        -   第四步刷新查询方式 textedit 状态
            -   更新 textedit 状态
        -   第五步刷新设备图标
    -   在所有改变后重新连接（通过通知或任何方式）
        -   更新设备（存储）和 DeviceState（易变）
    -   在重新连接/断开连接后，在远程视图中更新在线状态

## 改善围绕设备能力的用户消息

-   当可能发生错误时，更新用户消息
    -   当点击一个禁用的按钮时，打开弹出窗口显示为什么它被禁用
        -   在按钮上显示一个信息指示器，以表明可以在点击时接收到信息？
        -   耳机模式被禁用 -> 因为设备不支持此应用的耳机模式
        -   音量控制被禁用 -> 因为音频正在通过 HDMI 输出，它不支持音量控制？
    -   当积极扫描设备且没有找到新的设备时，显示一个警告消息在设备列表下方
        -   “我们无法唤醒您的Roku”（了解原因）（X）
        -   了解更多显示一个可能发生此问题的一些原因的弹出窗口
            -   确保您的设备已开机并连接到与您的应用程序相同的 wifi 网络。如果这还是没有用，请尝试手动添加设备。
            -   链接 https://roam.msd3.io/manually-add-tv.md 和 https://support.roku.com/article/115001480188 进行更多故障排查或聊天
-   为 supportsWakeOnWLAN 和 supportsMute 添加徽章

## 支持 ecp textedit

-   更新键盘处理以在 `KeyboardEntry` 上支持 ecp-textedit
    -   当 textedit 打开时显示键盘
    -   当 textedit 关闭时隐藏键盘
    -   测试将复制 + 选择/删除插入 textedit 字段是否如预期工作
    -   如果支持 ecp-textedit，允许选择、删除文本和移动光标。如果支持此功能，只需在每次更改时重发文本即可。
    -   如果不支持 ecp-textedit，则回退到当前的发送键行为
    -   在 macOS 上显示当启用 textedit 时的指示器
    -   在 macOS 上允许 cmd+v 和 cmd+c 和 cmd+x 复制粘贴从/到缓冲区

键盘 ECP 会话命令（备注）

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## 在放弃支持iOS 17/macOS 15（2025）时更新

-   使用预览特性将样本数据注入预览
    -   如何在 iOS 17 仍然是一个因素的情况下做到这一点？
    -   如何在 iOS 17 仍然是一个因素的情况下使用 @Previewable 在预览中？？
-   SwiftData
    -   使用新的 #Index 宏进行模型
    -   使用新的 #Unique 宏进行模型
    -   使用批量删除
-   TipKit
    -   使用 CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698