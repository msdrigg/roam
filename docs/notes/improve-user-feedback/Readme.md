# Need to improve user messaging to handle weird error cases

## Consider looking for a designer to help improve the UI of the app

## Make error badges look better

-   Keep them out of the way of the user + dismisable but make them more native
-   Make them interactable in an intuitive way
    -   Click on them to show more info + dismiss
    -   Look into transit app for good badges

## Make adding a device a more flowy process

-   Make it a wizard that walks you through getting the IP address from the TV and entering it

## Improve handling on apple watch

-   Make it show "Set settings to enabled" flow if they are set to limited (403 error) and we are using apple watch
    -   Pop-up to enter this flow from home screen if they are connecting to a disabled TV
    -   Auto-enter this flow if they are adding a bad device
-   Show a 'Connection disabled' error message if they open a watch with a TV set to that
-   Add an IP scan using canConnectHttp

## Add a better display for device capabilities/info

-   Show headphones mode support / Wake-on-lan support / fast-power-on support
-   Bottom sheets/flows for each of these, what they mean and how to fix them (e.g. turn on fast-power-on)
    -   Maybe auto-navigate to this setting using device intents?
-   Add tips to auto-enter these flows

## Make settings more easily reachable

-   I don't think it's clear that settings is behind "Scanning for devices".
-   We should probably find a different place to put it
-   Alternatively we could drop settings entirely
    -   Make auto-scanning the default. Show settings in top bar for ios and in top-menu for others
    -   Is this going to cause a problem for users if we do it like this? How to answer this question?

## Optimize for the 1 TV Use Case

-   Something like volume?
    -   Bottom device selector if there are more devices
    -   Don’t show controls that aren’t available (input hides/shows)
-   Optional menu-bar only (with setting)
-   Top bar shows name with settings
-   But I like the dropdown -> settings
-   Can I make my auto-discovery good enough that there isn’t a need for settings? (IP-scan in background much slower)

## Add the window min-size animation

-   Things 3 screen recording shows demo.
-   Check objc code from paper dev - https://papereditor.app/dev#gimmicks
