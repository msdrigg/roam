---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## 关于 Roam

Roam 满足您想要的一切，且没有您不需要的

-   支持 Mac，iPhone，iPad，Apple Watch，Vision Pro 或 Apple TV！
-   智能平台集成，Mac 上的键盘快捷键，使用 iOS 的硬件音量键控制电视音量
-   使用快捷键和小组件即可在不打开应用的情况下控制您的电视！
-   Mac，iPad，iPhone，VisionOS 和 Apple TV（通过设备播放电视的音频）都支持耳机模式（也称为私人听听）功能
-   打开应用时立即发现本地网络上的设备
-   使用苹果原生的 SwiftUI 设计系统则设计直观
-   快速且轻量，对所有设备来说均不足 8 MB，并能在半秒内打开！
-   开源 （https://github.com/msdrigg/roam）

## 常见问题

-   如果 Roam 没有自动发现我的电视，我能做些什么
    -   [查看这里](/manually-add-tv)
-   为什么我的电视上的耳机模式（也称为私人收听）不起作用？
    -   目前耳机模式在一些电视上不能工作。如果 Roam 的耳机模式无法工作，但是 Roku 官方应用的耳机模式可以工作，那么请通过邮件将您的 Roku 模型名称及任何其他相关的信息分享至 [roam-support@msd3.io](mailto:roam-support@msd3.io)。您的报告将有助于我确定在修复此 bug 时，该从哪里入手查找。
-   如果我有其他问题或只是想提供反馈该怎么办？
    -   如果是 bug，最好从应用程序中生成反馈报告
        -   进入 Roam 应用程序并打开设置页面
        -   点击“发送反馈”。这将生成一个可以和 roam_support（roam-support@msd3.io）分享的诊断报告
        -   如果你的应用程序崩溃，请确保在设置 -> 隐私和安全 -> 分析和改进中的分析功能已打开
            -   打开 "Share iPhone & Watch Analytics" 并打开 "Share With App Developers"，这样苹果会在您的应用崩溃时通知我
    -   如果是新功能的请求，您可以发送电子邮件（roam-support@msd3.io），直接在 Roam 应用中与我聊天（设置 -> 与开发人员聊天）或加入 [Roam Discord](https://discord.gg/FqaTNRccbG)。
-   为什么 iPad 的箭头键有时候不能工作？
    -   这是因为 iPadOS 有时会接管箭头键，把它们用来在我们可以检测到它们之前导航屏幕按钮
    -   您可以通过进入 设置 -> 无障碍 -> 键盘，禁用 "全键盘访问" 来解决此问题，另一种解决方案是转到 设置 -> 无障碍 -> 键盘 -> 全键盘访问 -> 命令 -> 基础，然后禁用 "Move Up"，"Move Down"，"Move Left" 和 "Move Right" 命令。  
-   为什么我在键盘上输入的内容不会显示在电视上？
    -   在一些 Roku App 中，应用程序会忽略硬件键盘的输入。您可以通过尝试在官方的 Roku App 中使用键盘输入功能来测试这是否是 Roam 的 bug 或者是应用的 bug
    -   已知存在 bug 的应用
        -   Prime Video
-   为什么 Roam 在我的 iPhone 和 mac 应用程序上可以工作，但是在我的 Apple Watch 上不能工作？
    -   WatchOS 应用通过电视的 ECP API 连接到电视，该 API 在某些 Roku TV 上必须启用。要启用它，请转到 **设置 -> 系统 -> 高级系统设置 -> 由移动应用控制**，然后确保 "网络访问" 已设置为 "许可"。

## 其他资源

如果您有任何问题或问题，请通过 [roam-support@msd3.io](mailto:roam-support@msd3.io) 与我联系。您也可以在 Roam 应用中直接和我聊天（设置 -> 与开发人员聊天）或者加入 [Roam Discord](https://discord.gg/FqaTNRccbG)。

-   [隐私政策](/privacy)
-   [GitHub 上的核心代码库](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [在应用商店下载](https://apps.apple.com/us/app/roam/6469834197)
-   [路线图](/upcoming-work)
-   [更新日志](/changes)
-   [已测试的 Roku 设备](/tested-tvs)