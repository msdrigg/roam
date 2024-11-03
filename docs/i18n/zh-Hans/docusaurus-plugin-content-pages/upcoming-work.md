---
hide_table_of_contents: true
---

# 最近的 Roam 工作

# 即将推出的 Roam 更新

- 为控制中心添加控制小工具：播放，静音，更改音量和选择！

## 路线图

-   更新键盘处理以支持 `KeyboardEntry` 上的 ecp-textedit
    - 当 textedit 打开时显示键盘
    - 当 textedit 关闭时隐藏键盘
    - 确保将粘贴 + 选择/删除到 textedit 字段的操作正常工作
    - 如果不支持 ecp-textedit，则使用当前的修改过的文本字段，如果支持，则使用标准的文本字段
    - 在 macOS 上，使用 cmdP 粘贴，用 cmdX + cmdC 复制/剪切
    - 如果不支持 ecp-textedit，则回退到当前的发送键的行为
    - 当启用 textedit 时，macOS 显示底部的文本字段
    - 在 macOS 上允许 cmd+v 和 cmd+c 和 cmd+x 从缓冲区复制粘贴

- 添加带计时的 +30 秒静音定时器
    - 长按静音以将其静音 +30 秒
    - 再次点击以取消静音并取消
    - 在静音按钮线下方显示指示器
        - 进度条具有线性进度指示器
        - 进度条有两个按钮：+30 秒，取消
        - 在主按钮面板下方显示，以便接近静音键
    - 将 +30 的配置修改为 30，15，60 秒的静音选项

- 在 iOS 上提供一个可选的最小化视图，以尽可能接近 siri 远程视图
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - 同时支持 visionos 手势

## 一般性未来想法

-   写一篇关于 discord 机器人的博客文章，并指向我的 MessageView
-   写一篇关于自动翻译及其逻辑的博客文章

-   制作自定义菜单栏图标

-   如何进行语音转文本或一般的语音命令？
    - 需要逆向工程 rokut 声音遥控器 udp 协议
    - 还是需要添加自定义语音转文本与远程按钮引擎？

-   自动截图捕捉
    -   使用 UITests 获取实际截图
    -   使用 AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w 获取帧中的截图
    -   或者其他
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   测试更多的键盘窍门
    -   GCKeyboard 是一个选项
    -   FocusEnvironment 也是一个选项
    -   确保不论用于 iOS 的解决方案不会破坏 message/keyboard 输入中的文本输入

-   添加一些对用户在其设备上实际进行的操作进行跟踪的事件（可能连接到 firebase 分析）
    -   跟踪谁在使用极简主义视图，他们正在做什么操作等

## Bug修复

-   弄清楚调用 `nextPacket` 的循环是否有意义。
    -   不是每 10ms 循环一次并希望时间正确，而是应该对收到的包进行遍历，并尝试在 `10ms * globalSequenceNumber + startHostTime` 的主机时间以及 `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   然后我可以从时钟上的 `for 等待` 循环切换到带有 `Task.sleep` 的 `while !Task.isCancelled` 循环。
    -   所以我们需要每 10 ms 循环一次并尝试将最后一个包拉下来然后在那个时候对其进行调度
    -   每当我们进行音频同步
        -   我们拥有最后一次渲染时间和一个同步包
        -   估计我们应该在同步时间 + 发送的包数
            -   渲染时间 + 附加

## 提升测试质量

-   UI 测试
    -   验证添加设备后，设备出现在设备选择器中并被 roam 选中
    -   验证用户可以导航到设置 -> 设备
    -   验证用户可以导航到设置 -> 消息
    -   验证用户可以导航到设置 -> 关于
    -   验证用户可以编辑/删除设备
    -   验证用户在添加设备后可以单击按钮
    -   验证用户看到无设备的横幅时会出现
    -   验证用户能看到 applinks
    -   参考 swiftdat testingmodelcontainer 用于 modelcontainers
    -   参考这里 https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad 了解如何设置测试

## App Clip

-   AppClip
    -   在设置 -> 设备上添加一个 "获取可共享的设备链接" 的按钮
        -   预生成所有 1.1M 的 app clip 代码并编码环形位置（0.5GB）
        -   制作一个 "获取该设备的可共享链接！" 的按钮，并在 app clip 代码的图片预览中（roam 颜色）
        -   当设备位置发生变化时，下载代码 + 链接并在设备上转换为 PNG
        -   让代码以图像的形式打开设备作为一个共享链接（带预览！）
    -   同样，使实际设备链接可共享

## 改进用户信息/状态管理方面的提示

-   更新信息/状态管理以更好地处理易变状态
    -   在断开连接、选择、点击按钮、切换到前台、打开应用时 -> 如果已断开连接，则重新启动重新连接的循环
    -   重连环路是指以步指数后退重新尝试失败的连接（0.5秒，双倍，10秒后退）。
    -   当连接到设备时，始终禁用网络警告
    -   当试图连接到设备或试图打开设备时，显示旋转的信息图标而不是灰色的点
    -   当成功启动设备时，显示从灰色 -> 旋转 -> 绿色的转换过程中的动画
    -   当使用 WOL 启动设备且在 5 秒后尚未连接，或者在启动设备后立即失败时，显示在 WiFi 下的警告消息
        -   “我们无法唤醒您的 Roku”（查看详细信息）（不再针对此设备显示该内容），（X）
        -   查看详细信息显示某些可能的原因
            -   您未连接到相同的网络（显示最后的设备网络名称。询问用户是否连接到这个网络）
            -   您的设备处于深度睡眠状态（最近不曾关闭设备）且无法睡醒
                -   您的设备并不支持 WWOL 并且连接到 wifi
                -   您的设备并不支持 WWOL 或 WOL
            -   您的网络没有以允许我们向设备发送唤醒命令的方式进行设置
    -   重连环节 = 逐步放大尝试重新连接到重新连接 ECP
        -   第一步，重新连接 ECP
        -   第二步，先监听通知
            -   处理 +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   确保我们可以处理这些请求以及其格式。
        -   第三步，刷新设备状态
        -   第四步，刷新查询的 textedit 状态
            -   更新 textedit 状态
        -   第五步，刷新设备图标
    -   在所有重新连接后的变化（通过通知或任何东西）
        -   更新设备（存储的）和设备状态（易变的）
    -   在重新连接/断开后，更新远程视图中的在线状态

## 改进设备能力方面的用户消息

-   当可能会出现错误时更新用户消息
    -   当点击被禁用的按钮时，打开弹出窗口显示为何禁用
        -   在按钮上显示信息指示器以表示可以点击获取信息？
        -   耳机模式被禁用 -> 因为设备不支持将耳机模式用于此应用
        -   音量控制被禁用 -> 因为音频正在通过 HDMI 输出，不支持音量控制？
    -   当活动扫描设备且未找到新的设备时，显示设备列表下方的警告消息
        -   “我们无法唤醒您的 Roku”（了解原因），（X）
        -   了解原因显示一个弹出窗口，其中包含一些可能发生此情况的原因
            -   请确保您的设备已开机并连接到与您的应用程序相同的 wifi 网络。如果这仍然不起作用，尝试手动添加设备。
            -   链接https://roam.msd3.io/manually-add-tv.md 和 https://support.roku.com/article/115001480188 以进一步故障排除或与聊天
-   为 supportsWakeOnWLAN 和 supportsMute 添加徽章

## ECP textedit 注解

键盘 ECP 会话命令（注解）

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## 当放弃对 iOS 17/macOS 14 的支持时更新（2026 年 2 月）

-   转身并删除 @available(iOS 18) 标签
-   使用预览特征将样本数据注入到预览中
    -   这该如何在仍考虑 iOS 17 的情况下实现？
    -   如何在仍考虑 iOS 17 的情况下在预览中使用 @Previewable？
-   SwiftData
    - 使用新的 #Index 宏替换模型
    - 使用新的 #Unique 宏替换模型
    - 使用批量删除
-   TipKit
    - 使用 CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698