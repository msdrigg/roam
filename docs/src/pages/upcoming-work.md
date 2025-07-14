---
hide_table_of_contents: true
---

# Roam Roadmap

## Coming Soon

-   Add more tips

    -   Add macOS tip for pasting links from youtube, max, ...
    -   Add macOS tip for keyboard entry
    -   Add tip for keyboard Shortcuts

-   Add long-press options to keys

    -   Long-press right arrow to ff
    -   Long-press left arrow to rr
    -   Long-press mute to long-mute
        -   Make the +30 configurable to 30, 15, 60 second mute options
        -   Show banner with +30 sec, x to cancel, background linear progress indicator
            -   Show underneath the main button panel so it's close to mute
        -   Cancels when muting again (and also does api call)

-   Fix bug in nextPacket loop

-   Automate screenshot upload with sync-metadata

-   Provide an optional Minimalist view on iOS that replicates siri remote's view closely

    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Support visionos gestures as well...
    -   Make standard buttons larger

## General Future Ideas

-   Make custom menu bar icon

-   How to do voice-to-text or general voice commands?

    -   See /docs/notes/voice-search

-   Try more keyboard hacks on iPad

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

-   Look at copying some of the descriptive features of other Roku remotes

    -   Explanations for local network permissions, etc…
    -   See Desktop -> RokuScanning -> 3rd party comparison
    -   Bottom sheet popup when you click on "Local network permissions not granted"

        -   Explain how to fix it
        -   Dismiss it from there

    -   WatchOS popup explaining when limited mode is on for devices (query /device/apps and check if it returns 4xx error)

        -   Whole entry flow where you click "Try again" after entering or "Cancel"

    -   Embed links to roam.msd3.io for concerns (instead of just listing them)

        -   Change info bubbles to disclosure buttons (drop down below) and from that disclosure, say "Click here to read more" to open roam

    -   On macOS (and maybe others), +add a device manually doesn't take you into that device view

    -   Remove info from device detail view

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
-   Add badge for supportsWakeOnWLAN and supportsAudioControls

## To update when dropping support for iOS 17/macOS 14 (Feb 2026)

-   Go around and remove @available(iOS 18) tags
-   Use preview traits to inject sample data into previews
-   SwiftData
    -   Use new #Index macro for models
    -   Use new #Unique macro for models
    -   Use batch deletion
-   TipKit
    -   Use CloudkitContainer https://developer.apple.com/videos/play/wwdc2024/10070/?time=698
