---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## 关于 Roam

Roam 提供你想要的一切，并去除了你不需要的功能

-   支持在 Mac、iPhone、iPad、Apple Watch、Vision Pro 或 Apple TV 上运行！
-   智能平台集成，Mac 上支持键盘快捷键，iOS 上可通过硬件音量键控制电视音量
-   使用快捷方式和小部件，无需打开应用即可直接控制电视！
-   耳机模式（即私人聆听）支持 Mac、iPad、iPhone、VisionOS 和 Apple TV（可通过你的设备播放电视音频）
-   打开应用即刻在本地网络发现你的设备
-   直观设计，采用 Apple 原生 SwiftUI 设计系统
-   体积小巧，高效快速，所有设备下均小于 8 MB，打开应用不到半秒！
-   开源（https://github.com/msdrigg/roam）

## 功能特性

-   遥控器功能
    -   Roam 包含标准的 Roku 遥控器功能，包括方向键、选择、返回、主页、播放/暂停等，以及在 Roku 支持的情况下的相关电视按键。
    -   由于 Roku Stick 仅支持 HDMI，无法通过 Roam 发送的 Roku 网络命令控制电视音量，因此音量调节在这些设备上可能不可用。
-   键盘输入
    -   在 macOS 上，没有单独的键盘按钮。当 Roam 窗口获得焦点时，Mac 键盘即可自动与电视交互。
    -   在 iOS 和 iPadOS 上，遥控器顶部有键盘按钮。
    -   watchOS 目前不支持键盘功能。
    -   某些 Roku 应用不支持从远程应用输入键盘内容。Prime Video 就是一个已知例子，在该应用内键盘输入可能无法生效，因为它不接受远程输入。
-   耳机模式/私人聆听
    -   在支持的 Roku 设备上，通过您的设备播放电视音频，实现私人聆听。
    -   在 Mac、iPad、iPhone、VisionOS 和 Apple TV 上获得支持，但部分 Roku 电视可能无法正常使用该功能。

## 常见问题

-   如果 Roam 无法自动发现我的电视怎么办
    -   [请见此处](/manually-add-tv)
-   Roam 在我的 Apple Watch 上无法正常工作
    -   请前往 **设置 -> 系统 -> 高级系统设置 -> 通过移动应用控制**，确保已设为 **允许/Permissive**
-   为什么耳机模式（即私人聆听）在我的电视上无法使用？
    -   耳机模式目前在部分电视上可能无法正常使用。如果在 Roam 中无法使用耳机模式，而在官方 Roku 应用中可以，请通过电子邮件 [roam-support@msd3.io](mailto:roam-support@msd3.io) 提供你的 Roku 型号及相关信息。你的反馈有助于我定位和修复此 Bug。
-   如果遇到其他问题或想要反馈建议怎么办？
    -   如果是 Bug，建议在应用内发起反馈报告
        -   进入 Roam 应用，打开设置页面
        -   点击“发送反馈”。这将生成一份诊断报告，便于通过 roam 支持邮箱（roam-support@msd3.io）共享
        -   如果应用发生崩溃，请确保开启了设置 -> 隐私与安全 -> 分析与改进
            -   打开“共享 iPhone 与 Watch 分析”，然后开启“与开发者共享”，这样应用崩溃时 Apple 能向我报告异常
    -   如果你有新功能需求，可以通过邮箱（roam-support@msd3.io）、在 Roam 应用中直接与我交流（设置 -> 和开发者聊天），或加入 [Roam Discord](https://discord.gg/FqaTNRccbG) 与我沟通。
-   为什么我的 iPad 有时方向键无法工作？
    -   这是因为 iPadOS 有时会捕获方向键用于界面导航，使 Roam 无法检测到这些按键
    -   你可以通过前往 设置 -> 辅助功能 -> 键盘 并关闭“完全键盘访问”，或进一步进入 设置 -> 辅助功能 -> 键盘 -> 完全键盘访问 -> 命令 -> 基本，将“上移”、“下移”、“左移”、“右移”命令关闭来解决。
-   为什么我在键盘上输入内容无法在电视上显示
    -   部分 Roku 应用会忽略实体键盘输入。你可以尝试在官方 Roku 应用里使用键盘输入功能，判断是 Roam 的问题还是该应用本身不兼容。
    -   在 macOS 上，无需键盘按钮，Roam 窗口获得焦点时即可自动输入。iOS 和 iPadOS 上请使用遥控器顶部的键盘按钮。watchOS 当前不支持键盘输入功能。
    -   已知有问题的应用
        -   Prime Video
-   为什么 Roam 能在我的 iPhone 和 Mac 上用，但 Apple Watch 用不了？
    -   WatchOS 端通过电视的 ECP API 连接，有些 Roku 电视需手动开启此功能。请前往 **设置 -> 系统 -> 高级系统设置 -> 通过移动应用控制**，确保“网络访问/Network Access”设为“允许/Permissive”

## 其他资源

如有其他问题或疑问，请通过邮件联系我：[roam-support@msd3.io](mailto:roam-support@msd3.io)。你还可以在 Roam 应用内（设置 -> 和开发者聊天）向我反馈，或加入 [Roam Discord](https://discord.gg/FqaTNRccbG) 参与讨论。

-   [隐私政策](/privacy)
-   [核心仓库（GitHub）](https://github.com/msdrigg/roam)
-   [Roam Discord 社区](https://discord.gg/FqaTNRccbG)
-   [App Store 下载地址](https://apps.apple.com/us/app/roam/6469834197)
-   [开发路线图](/upcoming-work)
-   [更新日志](/changes)
-   [已测试的 Roku 设备](/tested-tvs)