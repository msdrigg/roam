---
hide_table_of_contents: true
---

# Roam 路线图

## 完成的工作和下次更新

-   增加了控制微件：播放、静音、更改音量和从控制中心选择！
-   对许多roku应用添加了更好的文本字段处理
    -   当文本编辑可用时自动打开文本字段
    -   从 macOS（带键盘）复制、剪切、粘贴
    -   在 iOS 上复制、剪切、粘贴 + 常规编辑
-   围绕局域网权限和连接性的更好的报告
-   改进了键盘功能
-   连接稳定性提高

## 即将到来

-   向键添加长按选项
    -   向右箭头长按以进入快进模式
    -   向左箭头长按以进入快退模式
    -   长按静音以实现长时间静音
        -   将+30的配置设置为30、15、60秒静音选项
        -   显示横幅，显示+30秒，x以取消，背景线性进度指示器
            -   在主按钮面板下方显示，靠近静音按钮
        -   再次静音时取消（同时进行 API 调用）
-   修复 macOS 微件

-   未来：在 iOS 上提供可选的极简视图，它精确地复制了 siri remote 的视图
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   同时支持 visionos 手势...

## 一般的未来想法

-   制作自定义菜单栏图标

-   如何进行语音转文本或一般的语音命令？

    -   需要反向工程 roku 语音远程 udp 协议
    -   或需要添加自定义文本到语音的远程按钮引擎？

-   自动截图捕获

    -   使用UITests获取所有设备尺寸+ locales的实际截图
    -   使用 AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w 在帧中获取截图
    -   或其他
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   在iPad上尝试更多键盘技巧

    -   GCKeyboard 之一
    -   对于 2 的 FocusEnvironment
    -   确保 iOS 中使用的任何解决方案不会破坏消息/键盘输入中的文本输入

-   UI 测试
    -   测试当设备被添加时，它会出现在设备选择器中，并被roam选择
    -   测试用户能否导航至设置 -> devices
    -   测试用户能否导航至设置 -> 消息
    -   测试用户能否导航至设置 -> 关于
    -   测试用户能否编辑/删除设备
    -   测试用户在设备添加后能否点击按钮
    -   测试用户是否看到没有设备时的 横幅
    -   测试用户是否看到applinks
    -   参考swiftdat testingmodelcontainer获取modelcontainers
    -   参考此处 https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad 设置测试

## Bug 修复

-   弄清楚对`nextPacket`的循环调用是否有意义。
    -   而不是每10ms循环一次并希望时间正确，我应该在接收的数据包上循环，尝试将它们安排在主机时间 `10ms * globalSequenceNumber + startHostTime` 和 sampleTime 到 `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   然后我可以从时钟上的`for await`循环切换到一个`while !Task.isCancelled`循环，并在其中加入`Task.sleep`。
    -   所以我们需要每10毫秒循环一次，并尝试获取最后一个包，然后在那个时间安排它
    -   每当我们做一个音频同步
        -   我们有最后的渲染时间 + 一个同步包
        -   估计我们应该在+同步时间发送出去的包的数量
            -   渲染时间 + 额外的

## 改进用户周围信息/状态/能力管理的消息

-   使用 WOL 打开设备并在5秒后未连接，或打开设备并立即失败时，在wifi消息下面显示警告消息
    -   “我们无法唤醒您的Roku”（了解更多）（不再为此设备显示）（X）
    -   了解更多显示一些可能的原因
        -   您没有连接到同一网络（显示最后的设备网络名称。询问用户是否连接到此网络）
        -   您的设备处于深度睡眠状态（最近没有关机）不能唤醒
            -   您的设备不支持 WWOL 并且已连接到 wifi
            -   您的设备不支持 WWOL 或 WOL
        -   您的网络未设置为允许我们向设备发送唤醒命令
-   当点击一个禁用的按钮时，显示通知，说明它为什么被禁用了
    -   在按钮上显示一个信息指示器，表示可以在点击时接收信息？
    -   禁用耳机模式 -> 因为设备不支持此应用的耳机模式
    -   音量控制禁用 -> 因为音频正在通过 HDMI 输出，它不支持音量控制？
-   当正在扫描设备且没有找到新设备时，在设备列表下方显示警告消息
    -   “我们无法唤醒您的Roku”（了解原因），（X）
    -   了解更多显示一个弹出窗口，列出了这种情况可能发生的原因
        -   确保您的设备已经开启并连接到应用与您相同的 wifi 网络。如果仍然不能工作，尝试手动添加设备。
        -   链接 https://roam.msd3.io/manually-add-tv.md 和 https://support.roku.com/article/115001480188 更多故障排除或聊天
-   为supportsWakeOnWLAN和supportsAudioControls添加徽章

## 在放弃支持 iOS 17/macOS 14 的支持时更新（2026年2月）

-   去掉 @available(iOS 18) 标签
-   使用预览特性将样本数据注入预览
-   SwiftData
    -   对模型使用新的 #Index 宏
    -   对模型使用新的 #Unique 宏
    -   使用批量删除
-   TipKit
    -   使用CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698