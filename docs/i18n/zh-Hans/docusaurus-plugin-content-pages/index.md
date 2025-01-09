---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## 关于Roam

Roam提供你想要的一切，而没有你不想要的

-   可在Mac、iPhone、iPad、Apple Watch、Vision Pro或Apple TV上运行！
-   通过Mac上的键盘快捷方式、iOS上使用硬件音量按钮控制电视音量的智能平台集成
-   使用快捷方法和窗口控件无需打开应用程序即可控制您的电视!
-   支持在Mac、iPad、iPhone、VisionOS和Apple TV上使用耳机模式（又名私人聆听）（通过您的设备播放电视的音频）
-   在你打开应用程序的时候立即在你的本地网络上发现设备
-   使用苹果原生SwiftUI设计系统的直观设计
-   快速且轻量级，在所有设备上不到8MB，且在不到半秒内打开!
-   开源 (https://github.com/msdrigg/roam)

## 常见问题

-   我能做什么如果Roam不能自动发现我的电视
    -   [在这里查看](/manually-add-tv)
-   为什么我电视的耳机模式（又名私人聆听）不能使用?
    -   目前在一些电视上耳机模式还不能使用，如果你的电视与Roam的耳机模式不能配合使用，但是可以与官方的Roku应用配合使用，请通过邮件将你的Roku模型名称和其他相关信息发给 [roam-support@msd3.io](mailto:roam-support@msd3.io)。你的报告将会帮助我找到解决这个问题的方式。
-   如果我有另一个问题或我只是想提供反馈怎么办？
    -   如果是bug，最好是从应用程序中初始化一个反馈报告
        -   打开Roam应用并打开设置页面
        -   点击 "发送反馈"，这样可以生成一个能够共享给roam支持（roam-support@msd3.io）的诊断报告
        -   如果你的应用程序崩溃，请确保在设置->隐私和安全->分析和改进方面打开你的分析
            -   打开 "分享 iPhone 和 Watch 分析"，然后打开 "与应用开发者分享"，这样当你的应用崩溃时苹果会向我报告
    -   如果是要求新功能的请求，你可以直接发邮件（roam-support@msd3.io）或直接在Roam应用程序中与我聊天 (设置 -> 与开发者聊天）
-   为什么iPad上的箭头键有时候不能使用?
    -   是因为iPadOS有时候会接管了箭头键，并在我们检测到他们之前使用它们来导航屏幕按钮
    -   你可以通过进入设置->辅助功能->键盘并禁用 "全键盘访问" 或者进入设置-> 辅助设施->键盘->全键盘访问->命令->基本，并禁用 "向上移动"、"向下移动"、"向左移动" 和 "向右移动" 命令来解决这个问题
-   为什么在我的键盘上打字并没有在电视上显示
    -   在一些Roku应用中，应用程序会忽略硬件键盘输入，你可以测试这是否是Roam的bug还是该应用的bug，方法是尝试在官方的Roku应用程序中使用键盘输入功能，如果这个功能可以使用的话
    -   已知问题的应用
        -    Prime Video
-   为什么Roam在我的iPhone和mac app上可以工作但是在我的Apple Watch上不行？
    -   WatchOS应用连接到电视是通过电视的ECP API，这在一些Roku电视上需要启用，启用它请进入**设置 -> 系统 -> 高级系统设置 -> 由移动app控制** 并确保 "网络访问" 设置为 "宽松"

## 其他资源

如果你有任何问题或问题，请联系我：[roam-support@msd3.io](mailto:roam-support@msd3.io)。你也可以直接在Roam应用程序中与我交谈 (设置 -> 与开发人员聊天)。

-   [隐私政策](/privacy)
-   [GitHub上的核心仓库](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [在应用商店下载](https://apps.apple.com/us/app/roam/6469834197)
-   [路线图](/upcoming-work)
-   [已测试的Roku设备](/tested-tvs)