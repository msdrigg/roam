---
hide_table_of_contents: true
---

# Roam Roadmap

## Completed Work for Next Update

- Added control widgets: Play, Mute, Change Volume and Select from Control center!
- Added better text field handling for many roku apps 
    - Auto-open text field when text edit is available
    - Copy, Cut, Paste from macOS (with keyboard)
    - Copy, Cut, Paste + Generalized edit on iOS
- Better reporting around local network permissions and connectivity
- Connection stability improvements

## Coming Soon

-   Add long-press options to keys
    - Long-press right arrow to ff
    - Long-press left arrow to rr
    - Long-press mute to long-mute
        -   Make the +30 configurable to 30, 15, 60 second mute options
        - Show banner with +30 sec, x to cancel, background linear progress indicator
            -   Show underneath the main button panel so it's close to mute
        - Cancels when muting again (and also does api call)
-   Fix macOS widgets

-   Future: Provide an optional Minimalist view on iOS that replicates siri remote's view closely
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Support visionos gestures as well...

## General Future Ideas

-   Write a blog post about the discord bot and point to my MessageView
    - Make messageView more self-contained
-   Write a blog post about the auto-translation and logic around that
-   Write a blog post about NWConnection vs URLSession for websockets
-   Write a blog post about custom keyboard shortcuts
-   Write a blog post about ECP Textedit API
-   Write a blog post about control center widgets

-   Make custom menu bar icon

-   How to do voice-to-text or general voice commands?
    - Need to reverse-engineer the roku voice remote udp protocol
    - Or need to add custom text-to-speech with remote button engine?

-   Automate Screenshot Capture

    -   Use UITests to get actual screenshots for all device sizes + locales
    -   Use AppScreens https://appscreens.com/user/project/DRxTFSSIQtuU0y9Eew4w to get the screenshots in the frames
    -   Or something else
        -   https://www.figma.com/community/file/886620275115089774
        -   https://www.figma.com/community/file/1071476530354359587/app-store-screenshots?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.figma.com/community/file/1256854154932829222/free-app-store-screenshot-templates?searchSessionId=lxw3ep02-oubp844ov8
        -   https://www.canva.com/templates/s/iphone/

-   Try more keyboard hacks for iPad
    -   GCKeyboard for one
    -   FocusEnvironment for 2
    -   Ensure that whatever solution gets used for iOS doesn't break text entry in messages/keyboard entry

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

## Bug Fixes

-   Figure out if the loop of calls to `nextPacket` make sense.
    -   Instead of looping every 10ms and hoping the timing is correct, should I instead be looping over received packets and trying to schedule them at host time `10ms * globalSequenceNumber + startHostTime` and sampleTime to `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    -   Then I can switch from a `for await` loop over the clock to a `while !Task.isCancelled` loop with a `Task.sleep` in it.
    -   Okay so we need to loop every 10 ms and try to pull the last packet off and then schedule it at that time
    -   Whenever we do an audio sync
        -   We have lastRenderTime + a sync packet
        -   Estimate the packet number we should be sending out at + the sync time
            -   Render Time + additional

## Improve user messaging around info/status/capabilities management

-   When powering on the device with WOL and not connecting after 5 seconds, or when powering on the device and immediately failing, show a warning message underneath the wifi one
    -   “We weren’t able to wake your Roku” (Find out more) (Don’t show again for this device), (X)
    -   Find out more shows some reasons why
        -   You aren’t connected to the same network (Show last device network name. Ask if the user is connected to this network)
        -   Your device is in deep sleep (wasn’t powered down recently) and can’t be woken up
            -   Your device doesn’t support WWOL and is connected to wifi
            -   Your device doesn’t support WWOL or WOL
        -   Your network isn’t setup in a way to allow us to send wakeup commands to the device
-   When clicking on a disabled button, shown notification indicating why it’s disabled
    -   Show a info indicator on the button to indicate that information can be received when it’s clicked?
    -   Headphones mode disabled -> because device doesn’t support headphones mode to this app
    -   Volume control disabled -> because the audio is outputting over HDMI which does not support volume controls?
-   When actively scanning for devices and no new ones are found show a warning message underneath the device list
    -   “We weren’t able to wake your Roku” (Find out why), (X)
    -   Find out more shows a popup with some reasons why this may be happening
        -   Make sure your device is powered on and connected to the same wifi network as your app. If this still doesn't work, try adding the device manually.
        -   Link https://roam.msd3.io/manually-add-tv.md and https://support.roku.com/article/115001480188 for more troubleshooting or chat
-   Add badge for supportsWakeOnWLAN and supportsMute

## To update when dropping support for iOS 17/macOS 14 (Feb 2026)

-   Go around and remove @available(iOS 18) tags
-   Use preview traits to inject sample data into previews
-   SwiftData
    -   Use new #Index macro for models
    -   Use new #Unique macro for models
    -   Use batch deletion
-   TipKit
    -   Use CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
