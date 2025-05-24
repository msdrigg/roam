---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## 关于 Roam

Roam 提供你需要的一切并摒弃多余内容

-   可在 Mac、iPhone、iPad、Apple Watch、Vision Pro 或 Apple TV 上运行！
-   智能平台集成：Mac 上支持键盘快捷键，iOS 上可通过硬件音量键控制电视音量
-   利用快捷方式和小组件，无需打开应用即可控制电视！
-   耳机模式（即“私人聆听”）支持 Mac、iPad、iPhone、VisionOS 和 Apple TV（可通过你的设备播放电视音频）
-   打开应用即可在本地网络中发现设备
-   采用苹果原生 SwiftUI 设计系统，界面直观
-   快速轻巧，所有设备下应用体积均小于 8 MB，启动时间小于半秒！
-   开源（https://github.com/msdrigg/roam）

## 常见问题

-   如果 Roam 无法自动发现我的电视，该怎么办
    -   [点击这里查看](/manually-add-tv)
-   Roam 在我的 Apple Watch 上无法正常运行
    -   请前往 **设置 -> 系统 -> 高级系统设置 -> 通过移动应用控制**，确保设置为 **宽松**
-   为什么耳机模式（即私人聆听）无法在我的电视上使用？
    -   某些电视目前不支持耳机模式。如果耳机模式在 Roam 中无法使用，但在官方 Roku 应用中可以，请将你的 Roku 型号和相关信息发送邮件到 [roam-support@msd3.io](mailto:roam-support@msd3.io)。你的反馈将帮助我定位并解决此问题。
-   如果我遇到其他问题或者有反馈意见怎么办？
    -   如果是 bug，建议直接在应用中提交反馈
        -   进入 Roam 应用，打开设置页面
        -   点击“发送反馈”。这会生成一份诊断报告，可以发送给 Roam 支持团队（roam-support@msd3.io）
        -   如果应用崩溃，请确保你已在 设置 -> 隐私与安全 -> 分析与改进 中开启分析
            -   打开“共享 iPhone 与 Watch 分析”，继续打开“与应用开发者共享”，这样当应用崩溃时苹果会反馈给我
    -   如是新功能需求，可以发送邮件（roam-support@msd3.io）、直接在 Roam 应用内聊天（设置 -> 与开发者聊天）或者加入 [Roam Discord](https://discord.gg/FqaTNRccbG)
-   为什么在 iPad 上有时方向键无法使用？
    -   因为 iPadOS 有时会优先使用方向键来导航屏幕按钮，从而导致我们无法检测到按键输入
    -   你可以进入 设置 -> 辅助功能 -> 键盘，关闭“完整键盘访问”；或者进入 设置 -> 辅助功能 -> 键盘 -> 完整键盘访问 -> 命令 -> 基础，将“上移”、“下移”、“左移”、“右移”命令关闭
-   为什么用键盘输入电视上无法显示？
    -   某些 Roku 应用会忽略硬件键盘输入。你可以通过尝试在官方 Roku 应用内使用键盘输入功能，判断是 Roam 的 bug 还是该应用本身的问题
    -   已知有此问题的应用：
        -   Prime Video
-   为什么 Roam 可以在我的 iPhone 和 Mac 上使用，但在 Apple Watch 上不可用？
    -   WatchOS 应用需通过电视的 ECP API 进行连接，该接口在部分 Roku 电视上需手动开启。需前往 **设置 -> 系统 -> 高级系统设置 -> 通过移动应用控制**，确保“网络访问”设置为“宽松”

## 其他资源

如有疑问或遇到问题，请联系我：[roam-support@msd3.io](mailto:roam-support@msd3.io)。你也可以在 Roam 应用内直接与我聊天（设置 -> 与开发者聊天），或加入 [Roam Discord](https://discord.gg/FqaTNRccbG)。

-   [隐私政策](/privacy)
-   [GitHub 核心仓库](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [App Store 下载](https://apps.apple.com/us/app/roam/6469834197)
-   [开发路线图](/upcoming-work)
-   [更新日志](/changes)
-   [测试过的 Roku 设备](/tested-tvs)