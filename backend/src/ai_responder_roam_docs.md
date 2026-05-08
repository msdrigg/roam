# Roam Support Notes

Roam is a free Roku remote app with no ads. It runs on Mac, iPhone, iPad, Apple Watch, Vision Pro, and Apple TV. It supports shortcuts, widgets, Siri, local network discovery, keyboard shortcuts on Mac, hardware volume controls on iOS, and private listening on supported devices.

Platform/device context:

- If support-only Device Info already shows the OS platform as macOS, iOS, or watchOS, do not ask what device or platform the user is using before answering. Roam behavior is unified across devices on the same platform.

Remote features:

- Roam includes the normal Roku remote controls, including directional buttons, select, back, home, play/pause, and related TV controls when the Roku supports them.
- Volume controls may not work on Roku Sticks because they are HDMI-only devices and cannot control TV volume through Roam's Roku network commands.
- On macOS, there is no keyboard button. When the Roam window is focused, the Mac keyboard works automatically with the TV.
- On iOS and iPadOS, there is a keyboard button at the top of the remote.
- watchOS does not have keyboard functionality at this time.
- Some Roku apps ignore keyboard input from remote apps. Prime Video is a known app where keyboard entry may not work because the Roku app does not accept it.
- Private listening plays TV audio through the user's device on supported Roku devices.
- Private listening is supported in Roam on Mac, iPad, iPhone, VisionOS, and Apple TV, but it does not work on every Roku TV.

Common discovery and connection fixes:

- If Roam cannot auto-discover a Roku TV, ask the user to confirm the phone or computer is on the same Wi-Fi network as the Roku, the TV is turned on, and Local Network permission is enabled for Roam.
- On iOS, Local Network permission is in Settings -> Apps -> Roam -> Local Network.
- On macOS, Local Network permission is in System Settings -> Privacy and Security -> Local Network -> Roam.
- Users can manually add a TV from Roam settings by choosing "Add a device manually" and entering the Roku IP address shown on the Roku under Settings -> Network -> About.
- Do not mention router admin pages, DHCP client lists, or no-remote workarounds unless the user specifically says they do not have a physical remote or another way to control the Roku.
- If the user only says they cannot connect or cannot find the TV, use normal same-Wi-Fi, TV-on, Local Network permission, and manual-add guidance first.
- If a previously working device stopped working after a home network configuration change, suggest deleting the saved device from Roam and scanning for it again.
- If the user explicitly says they have no remote/no TV control and need the TV's IP address, suggest checking the home router's admin interface or DHCP client list.
- If the user explicitly says they have no Wi-Fi and no physical remote, refer them to Roku's mobile app connection article: https://support.roku.com/article/115001480188
- The Roku IP address is usually in a private range such as 10.x.x.x, 172.x.x.x, or 192.168.x.x. Tell users not to use the gateway address.
- Roam talks to Roku devices over TCP port 8060 for commands and device state, UDP wake-on-LAN broadcast for wake, and UDP port 6970 for private listening audio.
- If a network uses port forwarding, the manual IP field can include a port, for example 192.168.8.242:8061.

Apple Watch and limited-control fixes:

- Some Roku TVs require Control by mobile apps to be permissive. On the Roku, go to Settings -> System -> Advanced System Settings -> Control by mobile apps and set Network Access to Permissive.
- If Roam works on iPhone or Mac but not Apple Watch, this Roku setting is a strong first thing to check.
- watchOS cannot turn the TV on through the standard wake API unless Fast TV Start is enabled on the Roku TV. If a watchOS user reports that they cannot power their TV on from Roam (but other controls work, or it works from iPhone/Mac), have them enable Fast TV Start on the Roku:
  - Press the Home button on the Roku TV remote.
  - Scroll up or down and select Settings.
  - Select System, then Power.
  - Select Fast TV Start.
  - Highlight "Enable Fast TV Start" and press OK on the remote to check the box.

Private listening:

- Private listening is supported on Mac, iPad, iPhone, VisionOS, and Apple TV, but it does not work on every Roku TV.
- If private listening works in the official Roku app but not in Roam, ask the user for the Roku model name and relevant details, then bring in human support.

Keyboard input and iPad arrows:

- If arrow keys sometimes do not work on iPad, iPadOS may be taking over keyboard navigation. The workaround is Settings -> Accessibility -> Keyboards and disabling Full Keyboard Access, or disabling the Move Up, Move Down, Move Left, and Move Right commands under Full Keyboard Access -> Commands -> Basic.
- If typing on a hardware keyboard does not show up on the TV, some Roku apps ignore hardware keyboard input. Ask the user to test the same field in the official Roku app. Prime Video is a known app with this problem.
- On macOS, do not tell users to look for a keyboard button. The Mac keyboard works automatically with the TV while the Roam window is focused.
- On iOS and iPadOS, users can open keyboard input from the keyboard button at the top of the remote.
- watchOS does not have keyboard functionality at this time.

Feedback and diagnostics:

- For bugs, ask the user to open Roam settings and use Send feedback so the app can generate a diagnostic report.
- Shared diagnostics are often sent accidentally, especially repeated diagnostic shares. If a user only shared diagnostics and did not describe a problem, most often ignore the diagnostic share instead of asking follow-up questions or escalating.
- If the app is crashing, ask them to enable Apple analytics sharing in Settings -> Privacy & Security -> Analytics & Improvements, including Share iPhone & Watch Analytics and Share With App Developers.
- For feature requests, users can email roam-support@msd3.io, chat in Roam from Settings -> Chat with the Developer, or join the Roam Discord.

Privacy:

- The app privacy policy says requested personally identifiable information is retained on the user's device and is not collected by the developer in that way.
- Error log data may be collected through third-party products and can include IP address, device name, OS version, app configuration, time/date of use, and statistics.

Known tested devices listed in the docs include Hisense Roku TV R6, Roku Ultra, Roku Stick, and TCL TV, with main remote and private listening marked working in that list.
