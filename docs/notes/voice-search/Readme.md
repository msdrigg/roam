# Voice Search

## Introduction

The voice control functionality is one of the final good features that separates my app from the official Roku app, and I have been trying several methods for a long time to develop this feature. Unfortunately there is no documentation and this is a very complex feature. Additionally there are no 3rd party implementations (open source or otherwise) to rely on to understand the protocol better.

## Future Research Ideas

1. Wait for WWDC 2025 to see if there are any AI API's that would help me implement this in-device
    - Ideally better transcription API's and some kind of NLU API's
2. Get and investigate a better packet capture from the Voice Remote Pro
    - Could it be PCM-encoded audio? I know they use this in other places?
    - Could it be LibSAS?
3. Investigate the /voice ECP API more fully
    - Does it send any data to the internet corresponding to the requests we send?
    - Can we send anything to this API to get it to respond in some way? Fuzzing? Guessing?
    - See if we can find the code in /bin/Application that handles the 8060 API and see if we can find the piece that handles this
4. Can I try to get a serial console on my old Roku TV motherboard? If so, maybe I could attach a debugger and step through some of the code, install root certs, re-dump the firmware, or use some other techniques...

## Implementation Possibilities

### Option 1: Mishmash of Apple pre-built models

1.  Can usee apple's speech recognition https://developer.apple.com/documentation/speech/
2.  Can use apple's language recognition + translation to english
3.  Can use apple's NLCLassifier to find which command is being executed
    -   e.g. play on TV
    -   e.g. open ...
4.  Can use translation + NLTagger to somehow extract movie/command/tv show/app... from the list
    -   Run replay_v1 or final_nlu_v3 or some other command on the TV to perform these actions

-   **Pros**
    -   Heavily uses apple's AI/Speech capabilities
    -   Less reliance on Roku API's
-   **Cons**
    -   Still somewhat reliant on Roku APIs -- e.g. need ability to figure out _replay_v1_

### Option 2: Pre-built/custom model?

-   Same as **Option 1** but do the entire NLU outside of Apple's API's

-   **Pros**
    -   Higher ceiling for performance -- could be using more finely tuned models
-   **Cons**
    -   More twiddling with ML models

### Option 3: Simple Speech-to-Text + Roku Voice APIs

-   Can use apple's speech recognition https://developer.apple.com/documentation/speech/
-   Figure out a way to send text opaquely to Roku

### Option 4: Voice Remote Pro API

-   The voice-remote pro API is a audio-streaming API that streams the whole audio conversation to the TV
-   TV handles speech-to-text, NLU, executing command

-   **Pros**
    -   In theory this will be a much simpler integration
    -   No Apple Speech Recognition dialog popup on first interaction
-   **Cons**
    -   Much more opaque protocol which in theory I may never figure out

### Option 5: No Roku API's

-   Do command extraction using methods from Options 1 or 2
-   Build in commands for "open <app>", "open <settings>", "press <button>"

-   **Pros**
    -   This is the only option with a clear implementation path
-   **Cons**
    -   Features are much more limited because "Open Columbo" wouldn't work b/c I don't have a way to download every apps' catalog

## Future: Text search

-   Add keyboard entry search to do the same searching without voice
-   Checkout how cardhop does their search--it's really good
