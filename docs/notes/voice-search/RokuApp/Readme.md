## Roku App API

### General API

So the Roku App API is built on several NLU-recognizers that it calls "fulfillers", I guess because they "fulfill" a voice command. When a voice command is initiated, the first step is that the app makes a request to `query-info-for-voice-service` and then receives a response back with the following items

-   Host device settings
    -   Closed Captions: On/Off
    -   EPG Hide OTT: true/false (not sure what this is)
    -   External Control Method: "ir"
    -   Fast Start: Enabled/Disabled
    -   Time display format: "12H"|"24H"
    -   TV Inputs: List of inputs and their names
-   Host device state
    -   Amoeba Identifiers (I believe this is something with Roku Ads)
    -   Available Voice Triggers: ["press_hold"] (not sure what this is)
    -   Display: on/off
    -   Guest Mode: true/false
    -   Is Overlay Supported: true/false
    -   Is AV Settings Overlay Supported: true/false
    -   Media: "none"
    -   Media Kids Directed: true/false
    -   Media Type: "none"
    -   Overlay: "none"
    -   Star Button settings (not sure what this is)
    -   UI: "home"
    -   Voice Events On Screen: {}
-   Roku Search Params
    -   List of search params to include in some kind of roku search (unknown)
-   Supported Fulfillers
    -   List of fulfillers the TV supports

Secondly it makes a query to `send-voice-events` including a `sessionId` and and `events` parameter. This query includes a list of fulfiller responses. Different voice commands end up using different fulfillers and each fulfiller could have multiple or a single request which it refers to as an `intent`. These intents often have parameters like `confidences` meaning how likely it is that this intent is the desired one, entities -- which are the thing that's getting requested or something. These intents are large complicated JSON bodies (see "RokuAppAPIRecordings.md" for some examples).

Additionally I can't send one query multiple times. I can only send each one 1x typically. I have tried changing the ID's but this didn't work

### Fulfiller Information

-   replay_v1
    -   This has a lot of capabilities -- seems to be a varied NLU
-   tts
    -   I've seen this one called, but I'm not sure what this does -- because it doesn't send much information over, just some session ids and such
-   channel_not_installed
-   error_v2
-   pop_up
-   dismiss_hud
-   execute_button
-   voice_hud_v2
-   channel_call_to_action
-   device_implemented
    -   I've seen this one called but not sure what it does
-   channel_implemented
    -   Not sure what this does -- I could see it being used to execute an in-app command or search
-   sleep_timer
-   direct_to_play
    -   Plays a show/movie by id directly in an app
-   confirmation
-   direct_to_detail
-   direct_to_zone
-   visual_search_results
    -   This pulls up an on-screen overlay with a collection of search results
-   homescreen_search_results
    -   I believe this shows homescreen search results for movies/apps/anything
-   roku_search_results
-   voice_hud_v3
-   help_hud_v2
-   time_hud

### Web API: voice-service.voice.roku.com

-   Roku doesn't actually do the analysis on-device. This makes sense because edge machine learning is hard. Instead it makes a request to a remote service (voice-service.voice.roku.com) to do the voice analysis.
-   Basically all of these intents are created by the remote service even the speech-recognition.
-   See my subfolder (voice-service.voice.roku.com) for more details.

### Next Steps

We are still in the information gathering phase so all work is about getting information on how this API works and how to replicate it

1. Need to figure out which intents are supported by typical Roku TV's
    - Need to build a database of Roku TV's used by my app's users and some identifiers about them
    - Include udn, user id, supported fulfillers, user error logs, device capabilities, ...
    - Need to make this opt-outable in roam settings with clear language on what I want for this
    - Need to update my privacy policy
    - Need to write a dedicated _What data I collect_ page on my website explaining what data I collect and how to opt out and what I use it for
    - This will also be useful for understanding what portion of my users can use headphones mode, ...
2. Need to understand what each intent does and what parameters it supports
    - Need to create easy tooling to go from "Idea for voice command" to "Capture intent". Currently this is a minute-long manual process.
    - Can I create a script to 1. Open ssh + tcp dump and send packets back 2. Parse it with some pcap parser to get websocket commands, 3. Find the right one and export it
        - ssh gl tcpdump -i any -U -s0 -w - 'host 192.168.8.125 and host 192.168.8.242' |
    - Then I can get a db with a lot of these intents
3. I could also find a way to setup a roku emulator where I simulate the roku ECP protocol
    - Starting points: https://github.com/lvcabral/brs-engine/blob/377bd8eb62bd252e8ff98dd7fb42981338340c9e/src/cli/ecp.ts#L67 and https://github.com/lvcabral/brs-desktop and maybe https://github.com/craigsjacobs/RokuSSDP
    - Ideally a server in swift or python but these js ones could work too
    - Then I could capture packets better but I could also also respond with different sets of fulfillers and see if the app responds differently
4. Try to block the app's internet access and see what the speech setup falls back to (or maybe it fails entirely)
5. Re-capture the traffic from the app to the TV to see if any raw audio stream is getting sent. Maybe it is also getting sent there...
6. Look through the android app extraction (./android) and see if there are any defined json objects that could be used to better understand these fulfillments

The goal of this is to understand the easiest way to send commands to the device. The goal is to find a command where

-   1. The TV does the command -> episode/tv linking
-   2. Ideally the TV does the whole parsing but if it's not possible then we will implement apple's nlp models
