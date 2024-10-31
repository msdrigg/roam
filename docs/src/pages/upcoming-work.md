---
hide_table_of_contents: true
---

# Most recent roam work

-   Localizations in many languages
-   Spanish, Portuges, French, German, Filipino, Chinese, Vietnamese, Arabic, Punjabi, Italian
-   Improve customized keyboard shortcut support on iPad even if Full Keyboard Access is turned on
-   UI Improvements
    -   Pretty buttons for scanning for devices
    -   Translucent windows on macOS
    -   Added some quick-response messages for common problems

# Upcoming Roam Updates

## General Improvements

-   Document the discord support bot and maybe duplicate it into a library

-   How to do voice-to-text or general voice commands?
    - Need to reverse-engineer the roku voice remote udp protocol

-   Add +30 second mute timer with countdown
    -   Hold mute to mute for +30 seconds
    -   Click again to cancel mute
    -   Show a top bar notification
        -   Progress bar has a linear progress indicator
        -   Progress bar has two buttons: +30 seconds, cancel
        -   Show underneath the main button panel so it's close to mute
    -   Make the +30 configurable to 30, 15, 60 second mute options

-   Automate Screenshot Capture

    -   Use UITests to get actual screenshots
    -   Use AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w to get the screenshots in the frames
    -   Or something else
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Test more keyboard hacks
    -   GCKeyboard for one
    -   FocusEnvironment for 2
    -   Ensure that whatever solution gets used for iOS doesn't break text entry in messages/keyboard entry
-   AppIntents
    -   Add control center app intents
        -   Use toggle for mute/unmute and power on/off
        -   Use buttons for everything else
        -   Use tint correct purple
        -   Make configurable just like widgets
        -   Make work with action hint
    -   Let siri/spotlight better see the things in my app somehow?
        -   Add universal links to the devices so siri can link to them?
        -   Ensure that semantic search works
        -   Implement transferrable via string/codeable for my app entities
            -   ProxyRepresentation
            -   CodableRepresentation
-   Provide an optional Minimalist view on iOS that replicates siri remote's view closely
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Support visionos gestures as well...
    -   Need to build the textedit api first
-   Add some event tracking on what actions users are actually doing on their devices (connect to firebase analytics maybe?)
    -   Track who is using minimalist view, what actions they are doing, etc...

## Bug Fixes

-   Figure out if the loop of calls to `nextPacket` make sense.
    -   Instead of looping every 10ms and hoping the timing is correct, should I instead be looping over received packets and trying to schedule them at host time `10ms * globalSequenceNumber + startHostTime` and sampleTime to `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Then I can switch from a `for await` loop over the clock to a `while !Task.isCancelled` loop with a `Task.sleep` in it.
    -   Okay so we need to loop every 10 ms and try to pull the last packet off and then schedule it at that time
    -   Whenever we do an audio sync
        -   We have lastRenderTime + a sync packet
        -   Estimate the packet number we should be sending out at + the sync time
            -   Render Time + additional
-   Nana Test fixes
    -   Option to turn off scanning for devices FULLY (leave on by default)
        -   Don’t mark a newly scanned device as selected automatically unless it was done in a foreground scan or a user added device
    -   Add broadcast interface, scan range and parse the flags properly for display in debug interface
    -   Ensure all my logs are not sensitized
    -   Make custom menu bar icon

## Improve Testing

-   UI Tests
    -   Test when device is added that it shows up in device picker and is selected by roam
    -   Test that user can navigate to settings -> devices
    -   Test that user can navigate to settings -> messages
    -   Test that user can navigate to settings -> about
    -   Test that user can edit/delete devices
    -   Test that user can click buttons once devices are added
    -   Test that user sees banner for no devices when it shows up
    -   Test that the user sees applinks
    -   Refer to swiftdat testingmodelcontainer for modelcontainers
    -   Refer to here https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad for how to setup tests

## App Clip

-   AppClip
    -   Add a "getAShareableLinkToThisDevice" button on settings -> device
        -   Pre-generate all 1.1M app clip codes and encode ring locations (0.5GB)
        -   Make a button to "Get a shareable link to the device!" with an image preview to the app clip code (roam color)
        -   Download the code + link and convert to PNG on device when a device location is changed
        -   Have the code open up the device as a shared link to an image (with preview!)
    -   Also make the actual device link sharable

## Improve user messaging around info/status management

-   Update Info/status management to better handle volatile state
    -   On disconnect, select, button click, move to foreground, app opened -> Restart reconnect loop if disconnected
    -   Reconnect loop is to exponentially backoff retrying failing connections (0.5s, double, 10s backoff)
    -   When connected to the device, always disable the network warnings
    -   When trying to connect to the device, or trying to power on the device, show spinning information icon instead of gray dot
    -   When powering on the device and succeeding, show an animation on transition from gray -> spinning -> green
    -   When powering on the device with WOL and not connecting after 5 seconds, or when powering on the device and immediately failing, show a warning message underneath the wifi one
        -   “We weren’t able to wake your Roku” (Find out more) (Don’t show again for this device), (X)
        -   Find out more shows some reasons why
            -   You aren’t connected to the same network (Show last device network name. Ask if the user is connected to this network)
            -   Your device is in deep sleep (wasn’t powered down recently) and can’t be woken up
                -   Your device doesn’t support WWOL and is connected to wifi
                -   Your device doesn’t support WWOL or WOL
            -   Your network isn’t setup in a way to allow us to send wakeup commands to the device
    -   Reconnect loop = Backing off Exponentially attempt to reconnect to reconnect ECP
        -   Reconnect ECP first
        -   Listen to notify second
            -   Handle +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   Make sure we can handle each of these requests and their format…
        -   Refresh device state third
        -   Refresh query-textedit-state fourth
            -   Update textedit state
        -   Refresh device icons fifth
    -   On all changes after reconnecting (through notify or anything)
        -   Update Device (stored) and DeviceState (voilatile)
    -   After reconnecting/disconnecting, update online status in remote view

## Improve user messaging around device capabilities

-   Update user messaging when errors may occur
    -   When clicking on a disabled button, open popover to show why it’s disabled
        -   Show a info indicator on the button to indicate that information can be received when it’s clicked?
        -   Headphones mode disabled -> because device doesn’t support headphones mode to this app
        -   Volume control disabled -> because the audio is outputting over HDMI which does not support volume controls?
    -   When actively scanning for devices and no new ones are found show a warning message underneath the device list
        -   “We weren’t able to wake your Roku” (Find out why), (X)
        -   Find out more shows a popup with some reasons why this may be happening
            -   Make sure your device is powered on and connected to the same wifi network as your app. If this still doesn't work, try adding the device manually.
            -   Link https://roam.msd3.io/manually-add-tv.md and https://support.roku.com/article/115001480188 for more troubleshooting or chat
-   Add badge for supportsWakeOnWLAN and supportsMute

## Support ecp textedit

-   Update keyboard handling to support ecp-textedit on `KeyboardEntry`
    -   Show keyboard when textedit is opened
    -   Hide keyboard when textedit closed
    -   Test that pasting + select/delete into the textedit field works as expected
    -   If ecp-textedit is supported, allow selecting, deleting text and moving cursor. Just re-send text each time it changes if this is supported.
    -   If ecp-textedit is not supported, fall back to current behavior of sending keys
    -   On macOS show an indicator when textedit is enabled 
    -   On macOS allow cmd+v and cmd+c and cmd+x to copy paste from/to the buffer

Keyboard ECP Session Commands (notes)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```

## To update when dropping support for iOS 17/macOS 15 (2025)

-   Use preview traits to inject sample data into previews
    -   How to do this with iOS 17 still being a factor?
    -   How to use @Previewable in previews with iOS 17 still a factor??
-   SwiftData
    -   Use new #Index macro for models
    -   Use new #Unique macro for models
    -   Use batch deletion
-   TipKit
    -   Use CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
