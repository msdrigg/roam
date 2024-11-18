---
hide_table_of_contents: true
---

# Roam 开发路线图

## 下次更新已完成的工作

- 添加了控制部件：控制中心的播放、静音、更改音量和选择！
- 为许多 roku 应用添加了更好的文本字段处理
    - 当文本编辑可用时自动打开文本字段
    - 从 macOS 复制、剪切、粘贴
    - 在 iOS 上复制、剪切、粘贴 + 推广编辑
- 更好的本地网络权限和连通性报告
- 连接稳定性改进

## 即将推出

-   当前进行中
    -   确保 iOS 上的文本输入不会进到键盘以下（就像现在正在做的那样）
    -   修复 macOS 部件
    -   把 iOS 版推到应用商店
        - 等待上诉后续
    -   在 iOS 和 macOS 上进行更好的测试，测试系统在以下情况下是否会重新连接并保持连接
        - 长时间等待后
        - 从后台重入时
        - 从 OFF 状态开启电视时
        - 重新连接到互联网时
        - 切换设备时

-   下一步：添加带倒计时的 +30 秒静音定时器
    -   长按静音键进行 +30 秒静音
    -   再次点击以取消静音并取消它
    -   在静音按钮下方显示指示器
        -   进度条有一个线性进度指示器
        -   进度条有两个按钮： +30 秒，取消
        -   在主按钮面板下方显示，以便靠近静音
    -   将 +30 配置为 30，15，60 秒静音选项

-   未来：提供一个可选的简洁视图在 iOS 上，紧密模拟 siri 遥控器的视图
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   也支持 visionos 手势...

## 一般未来想法

-   写一篇关于 discord bot 的博客文章并指向我的 MessageView
    - 使 messageView 更为自成体系
-   关于自动翻译和翻译逻辑的博客文章.
-   写一篇关于 NWConnection vs URLSession for websockets 的博客文章
-   写一篇关于自定义键盘快捷键的博客文章
-   写一篇关于 ECP Textedit API 的博客文章
-   写一篇关于控制中心部件的博客文章

-   制作自定义菜单栏图标

-   如何实现语音转文本或一般语音指令？
    - 需要反向工程 roku 语音遥控器 udp 协议
    - 或者需要添加自定义的文本转语音与遥控器按钮引擎？

-   自动截图捕捉

    -   使用 UITests 为所有设备大小 + 地区获取实际截图
    -   使用 AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w 将截图放在框架内
    -   还是其他的
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   尝试对 iPad 做更多键盘黑客
    -   GCKeyboard 为一
    -   FocusEnvironment 为二
    -   确保用于 iOS 的任何解决方案都不会打破消息/键盘输入中的文本输入

-   UI 测试
    -   测试当设备添加后，它是否显示在设备选择器中，并被 roam 选中
    -   测试用户是否能导航到 settings -> devices
    -   测试用户是否能导航到 settings -> messages
    -   测试用户是否能导航到 settings -> about
    -   测试用户能否编辑/删除设备
    -   测试用户添加设备后是否能点击按钮
    -   测试用户在没有设备出现时是否看到横幅
    -   测试用户是否看到 applinks
    -   利用 swiftdat testingmodelcontainer 来参考 modelcontainers
    -   访问 https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad 了解如何设置测试

## 问题修复

-   弄清楚对 `nextPacket` 进行的循环调用是否有意义
    -   不是每 10ms 循环一次，希望时间是正确的，而是应该遍历接收到的包，并尝试把它们安排在主机时间 `10ms * globalSequenceNumber + startHostTime` 和样本时间 `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   然后我可以从时钟的 `for await` 循环切换到一个带有 `Task.sleep` 的 `while !Task.isCancelled` 循环。
    -   所以我们需要每 10 ms 循环一次并尝试拉出最后的包，然后在那个时间安排它
    -   每当我们进行音频同步
        -   我们有 lastRenderTime + 一个同步包
        -   估算我们应该在哪个时间发出的包号
            -   Render Time + additional

## 改进用户围绕信息/状态/能力管理的消息

-   当使用 WOL 开启设备后 5 秒钟未连接，或者开启设备后立刻连接失败时，显示一个警告消息在 wifi 下方
    -   “我们无法唤醒您的 Roku” （了解更多） (不再显示此设备)（X）
    -   了解更多显示一些可能的原因
        -   您未连接到相同的网络 (显示上次设备网络名称. 询问用户是否连接到此网络)
        -   您的设备处于深度睡眠状态 (最近未断电) 无法唤醒
            -   您的设备不支持 WWOL 并已连接到 wifi
            -   您的设备不支持 WWOL 或 WOL
        -   您的网络设置无法让我们向设备发送唤醒指令
-   当点击被禁用的按钮时，显示通知说明禁用的原因
    -   在按钮上显示信息指示器，表明点击后可以接收信息？
    -   耳机模式禁用 -> 因为设备不支持对此应用的耳机模式
    -   音量控制禁用 -> 因为音频正在通过 HDMI 输出，不支持音量控制？
-   当主动扫描设备且未发现新设备时，在设备列表下方显示警告信息
    -   “我们无法唤醒您的 Roku” (查找原因) (X)
    -   了解更多显示一个弹窗，列出这种情况可能存在的原因
        -   确保设备已开机，且与应用连接到相同的 wifi 网络。如果仍然不起作用，尝试手动添加设备。
        -   链接 https://roam.msd3.io/manually-add-tv.md 和 https://support.roku.com/article/115001480188 以更多故障排除或聊天
-   为 supportsWakeOnWLAN 和 supportsMute 添加徽章

## 在放弃对 iOS 17/macOS 14 的支持时更新 (2026年2月)

-   删除 @available(iOS 18) 标签
-   使用预览特性将样本数据注入预览中
-   Swift数据
    -   使用新的 #Index 宏处理模型
    -   使用新的 #Unique 宏处理模型
    -   使用批量删除
-   TipKit
    -   使用 CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698