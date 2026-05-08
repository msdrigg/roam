---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## About Roam

Roam offers everything you want and nothing you don't

-   Runs on Mac, iPhone, iPad, Apple Watch, Vision Pro or Apple TV!
-   Smart platform integration with keyboard shortcuts on Mac, using hardware volume buttons to control TV Volume on iOS
-   Use shortcuts and widgets to control your TV without ever opening the app!
-   Headphones mode (a.k.a. private listening) support on Mac, iPad, iPhone, VisionOS, and Apple TV (play the audio from your TV through your device)
-   Discover devices on your local network as soon as you open the app
-   Intuitive design with apple's native SwiftUI design system
-   Fast and lightweight, less than 8 MB on all devices and opens in less than half a second!
-   Open source (https://github.com/msdrigg/roam)

## Features

-   Remote controls
    -   Roam includes the normal Roku remote controls, including directional buttons, select, back, home, play/pause, and related TV controls when the Roku supports them.
    -   Volume controls may not work on Roku Sticks because they are HDMI-only devices and cannot control TV volume through Roam's Roku network commands.
-   Keyboard input
    -   On macOS, there is no keyboard button. When the Roam window is focused, the Mac keyboard works automatically with the TV.
    -   On iOS and iPadOS, there is a keyboard button at the top of the remote.
    -   watchOS does not have keyboard functionality at this time.
    -   Some Roku apps ignore keyboard input from remote apps. Prime Video is a known example where keyboard entry may not work because the Roku app does not accept it.
-   Headphones mode/private listening
    -   Private listening plays TV audio through your device on supported Roku devices.
    -   Private listening is supported in Roam on Mac, iPad, iPhone, VisionOS, and Apple TV, but it does not work on every Roku TV.

## Common Issues

-   What can I do if Roam doesn't auto-discover my TV
    -   [See here](/manually-add-tv)
-   Roam isn't working correctly on my Apple Watch
    -   Please go to **Settings -> System -> Advanced System Settings -> Control by mobile apps** and make sure it is set to **Permissive**
-   Why doesn't headphones mode (a.k.a. private listening) work on my TV?
    -   Headphones mode currently isn't working on some TV's. If headphones mode doesn't work with Roam, but works with the official Roku app, please share your Roku's model name and any other relevant information in an email to [roam-support@msd3.io](mailto:roam-support@msd3.io). Your report will help me figure out where to look when trying to fix this bug.
-   What if I have another problem or just want to provide feedback?
    -   If it's a bug, it will be best to go initiate a feedback report from the application
        -   Go into the Roam app and open the settings page
        -   Click "Send feedback". This will generate a diagnostic report that can be shared with roam support (roam-support@msd3.io)
        -   If your app is crashing, also make sure your analytics are turned on in Settings -> Privacy & Security -> Analytics & Improvments
            -   Turn on "Share iPhone & Watch Analytics" and then turn on "Share With App Developers" so apple will report to me when your app crashes
    -   If it's a request for a new feature, you can send an email (roam-support@msd3.io), chat with me directly in the Roam app (Settings -> Chat with the Developer) or or join the [Roam Discord](https://discord.gg/FqaTNRccbG).
-   Why don't the arrow keys sometimes work on iPad?
    -   This is caused because iPadOS sometimes takes control of the arrow keys and uses them for navigating the screen buttons before we can detect them
    -   You can work arround this by going into Settings -> Accessiblity -> Keyboards and disabling "Full Keyboard Access" or alternatively going to Settings -> Accessiblity -> Keyboards -> Full Keyboard Access -> Commands -> Basic and disabling the "Move Up", "Move Down", "Move Left" and "Move Right" commands
-   Why doesn't typing on my keyboard show up on the TV
    -   On some Roku Apps the app ignores hardware keyboard entry. You can test if this is a Roam bug or a bug in the app by trying to use the keyboard entry feature in the official Roku App and checking if this works
    -   On macOS, there is no keyboard button because the Mac keyboard works automatically with the TV when the Roam window is focused. On iOS and iPadOS, use the keyboard button at the top of the remote. watchOS does not support keyboard input at this time.
    -   Apps with known bugs
        -   Prime Video
-   Why does Roam work on my iPhone and mac app work but not on my Apple Watch?
    -   The WatchOS app connects to the TV through the TV's ECP API, which must be enabled on some Roku TV's. To Enable it, go to **Settings -> System -> Advanced System Settings -> Control by mobile apps** and make sure "Network Access" is set to "Permissive"
-   Why can't I turn my TV on from my Apple Watch?
    -   Apple Watch can't use the standard wake API to turn the TV on unless **Fast TV Start** is enabled on the Roku TV. To enable it:
        -   Press the **Home** button on your Roku TV remote
        -   Scroll up or down and select **Settings**
        -   Select **System**, then **Power**
        -   Select **Fast TV Start**
        -   Highlight **Enable Fast TV Start** and press **OK** on the remote to check the box

## Other Resources

If you have any questions or issues, please contact me at: [roam-support@msd3.io](mailto:roam-support@msd3.io). You can also chat with me directly in the Roam app (Settings -> Chat with the Developer) or join the [Roam Discord](https://discord.gg/FqaTNRccbG).

-   [Privacy Policy](/privacy)
-   [Core Repository on GitHub](https://github.com/msdrigg/roam)
-   [Roam Discord](https://discord.gg/FqaTNRccbG)
-   [Download on the app store](https://apps.apple.com/us/app/roam/6469834197)
-   [Roadmap](/upcoming-work)
-   [Changelog](/changes)
-   [Roku Devices Tested](/tested-tvs)
