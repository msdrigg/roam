---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## 关于 Roam

Roam提供您所想要的一切，没有您不需要的

-   可在 Mac、iPhone、iPad、Apple Watch、Vision Pro 或 Apple TV上运行！
-   智能平台集成，包括在 Mac 上的键盘快捷键，以及在 iOS 中使用硬件音量按钮控制 TV 音量
-   使用快捷方法和小插件控制您的 TV，不需要每次都打开应用程序！
-   在 Mac、iPad、iPhone、VisionOS 和 Apple TV上支持耳机模式（又名私人聆听）（通过您的设备播放电视的音频）
-   一旦打开应用程序，就可以发现本地网络上的设备
-   使用苹果原生的 SwiftUI 设计系统，设计直观
-   快速且轻量，所有设备上少于8 MB，且无需半秒即可打开！
-   开源（https://github.com/msdrigg/roam）

## 常见问题

-   如果 Roam 无法自动发现我的 TV 我应该做什么
    -   [点击这里](/manually-add-tv)
-   我的 TV 上为什么无法使用耳机模式（又名私人聆听）？
    -   耳机模式目前在某些 TV 上无法使用。如果耳机模式无法在 Roam 中使用，但是可以在官方 Roku 应用程序中使用，请通过电子邮件向 [roam-support@msd3.io](mailto:roam-support@msd3.io) 分享您的 Roku 模型名称及任何其他相关信息。您的报告将帮助我找到修复此 bug 的方向。
-   如果我遇到另一个问题或只是想提供反馈怎么办？
    -   如果是 bug，最好从应用程序启动反馈报告
        -   进入 Roam 应用程序并打开设置页面
        -   单击“发送反馈”。这将生成可以与 roam 支持（roam-support@msd3.io）共享的诊断报告
        -   如果您的应用程序崩溃，也确保在设置 -> 隐私 & 安全 -> 分析 &改进中打开您的分析功能
            -   打开 "分享 iPhone & Watch 分析"，然后打开 "分享给应用开发者"，这样苹果就会在您的应用程序崩溃时向我报告
    -   如果是请求新功能，您可以直接发送电子邮件（roam-support@msd3.io），或者直接在 Roam 应用程序中与我聊天（设置 -> 与开发人员聊天）
-   为什么在 iPad 上箭头键有时不起作用？
    -   这是因为 iPadOS 有时会接管箭头键，并在我们能检测到它们之前用它们来导航屏幕按钮
    -   您可以通过进入设置 -> 辅助功能 -> 键盘并禁用 "全键盘访问" 或者进入设置 -> 辅助功能 -> 键盘 -> 全键盘访问 -> 命令 -> 基础并禁用 "向上移动"，"向下移动"，"向左移动" 和 "向右移动" 的命令来解决这个问题
-   为什么我在键盘上打字不会显示在电视上？
    -   在一些 Roku Apps 中，程序会忽略硬件键盘输入。如果这是 Roam 的 bug 还是程序的 bug，您可以在官方的 Roku App 中尝试使用键盘输入特性并检查是否有效
    -   已知存在 bug 的应用程序
        -   Prime Video
-   为什么 Roam 在我的 iPhone 和 mac 应用程序上有效，但是在我的 Apple Watch 上无效？
    -   WatchOS 应用程序通过 TV 的 ECP API 连接到 TV，某些 Roku TV 必须启用它。要启用，请转到 **设置 -> 系统 -> 高级系统设置 -> 通过移动应用程序控制**，并确保 "网络访问" 被设置为 "宽容"

## 其他资源

如果您有任何问题或问题，请联系我：[roam-support@msd3.io](mailto:roam-support@msd3.io). 您也可以直接在 Roam 应用程序中与我聊天（设置 -> 与开发人员聊天）。

-   [隐私政策](/privacy)
-   [GitHub上的核心存储库](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [在App Store上下载](https://apps.apple.com/us/app/roam/6469834197)
-   [路线图](/upcoming-work)
-   [更新日志](/changes)
-   [测试过的Roku设备](/tested-tvs)