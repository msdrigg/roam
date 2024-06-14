---
hide_table_of_contents: true
---

# Most recent roam work

- Localizations in many languages
- Spanish, Portuges, French, German, Filipino, Chinese, Vietnamese, Arabic, Punjabi, Italian
- Improve customized keyboard shortcut support on iPad even if Full Keyboard Access is turned on

# Upcoming Roam Updates

## Learnings to do
- Watch tipkit talk
- Watch talk "What’s new in Wallet and Apple Pay" to see if it has anything to do with app clip codes
- Watch "What’s new in device management" for business purposes
- Figure out how to let siri use my app more smoothly? 

- WatchOS
    - Make sure my app supports interactive widgets
- Offer shortcuts to get the last selected app/search an app /get the last selected device/search a device
- Improve windows
    - Consider tailoring window placement in visionOS/macOS
- Test more keyboard hacks
    - GCKeyboard for one
    - FocusEnvironment for 2
- Use preview traits to inject sample data into previews
    - How to do this with iOS 17 still being a factor?
- SwiftData
    - Add indices to swiftdata models?
    - Use new #Unique macro for swiftdata?
- AppIntents
    - Add control center app intents
        - Use toggle for mute/unmute and power on/off
        - Use buttons for everything else
        - Use tint correct purple
        - Make configurable just like widgets
        - Make work with action hint
    - Let siri/spotlight better see the things in my app somehow?
        - Add universal links to the devices so siri can link to them
        - Move to IndexedEntity to show in siri
        - Implement transferrable via string/codeable for my app entities
            - ProxyRepresentation
            - CodableRepresentation
- Migrate to swift 6 data concurrency


## Bug Fixes

- Consider SFSymbols 6 Updates
    - repeat continuous with the breathe transition for the headphones mode
    - use repeat transition for refreshing?
    - Use wiggle for disabled buttons?
- Ensure toolbar has identifier for remoteie
- Figure out if the loop of calls to `nextPacket` make sense.
    - Instead of looping every 10ms and hoping the timing is correct, should I instead be looping over received packets and trying to schedule them at host time `10ms * globalSequenceNumber + startHostTime` and sampleTime to `sequenceNumber * Int64(lastSampleTime.sampleRate) / packetsPerSec + startSampleTime`
    - Then I can switch from a `for await` loop over the clock to a `while !Task.isCancelled` loop with a `Task.sleep` in it.
- Figure out what causes data leak in case of long-running private listening after TV shuts off...
- Get keyboard shortcuts working on iPad even when Full Keyboard Access is turned on...
    - Ensure that whatever solution gets used for iOS doesn't break text entry in messages/keyboard entry
- Figure out what causes race condition when quickly clicking headphones mode keyboard shortcut 
    - ensure rtcp/rtp listeners are cancelled...
    - if they aren't work backwards up to why and fix
    - if they are, why aren't they stopping...
- Provide an optional Minimalist view that replicates siri remote's view closely
    - https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    - Support visionos gestures as well...
    - Need to build the textedit api first
- Add some Home Screen quick actions
- Add some event tracking on what actions users are actually doing on their devices (connect to firebase analytics maybe?)
    - Track who is using minimalist view, what actions they are doing, etc...
-  Support dynamic type with scaled buttons/text in my app
-  Switch to a custom pulse animation on my pulse button

## TipKit

- Add help text to some views for macos, visionOS
- Add tips for private listening
- Add tips for keyboard shortcuts
- Add tips for messaging the dev?
- Add tips for features that don't work when there is no API key (message developer, share diagnostics)
- Add tip for setting up global keyboard shortcuts via macos app
- https://fatbobman.com/en/posts/mastering-tipkit-advance/
- Use TipGroup for tips https://www.youtube.com/watch?v=raHy6XT3Rlc&list=WL&index=4
- Switch the initial "Connect a device to get started" into a tip
- Ensure tips are synced with icloud

## Improve Testing

-   UI Tests
    - Test when device is added that it shows up in device picker and is selected by roam
    - Test that user can navigate to settings -> devices
    - Test that user can navigate to settings -> messages
    - Test that user can navigate to settings -> about
    - Test that user can edit/delete devices
    - Test that user can click buttons once devices are added
    - Test that user sees banner for no devices when it shows up
    - Test that the user sees applinks
    - Refer to swiftdat testingmodelcontainer for modelcontainers
    - Refer to here https://medium.com/appledeveloperacademy-ufpe/how-to-implement-ui-tests-with-swiftui-a-few-examples-636708ee26ad for how to setup tests

## App Clip

-   AppClip
    -   Add a "getAShareableLinkToThisDevice" button on settings -> device
    -   Autogenerate app clip codes with that shareable link

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
    -   If ecp-textedit is supported, allow selecting, deleting text and moving cursor. Just re-send text each time it changes if this is supported.
    -   If ecp-textedit is not supported, fall back to current behavior of sending keys

Keyboard ECP Session Commands (notes)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```
