# Voice Search

## Introduction

The voice control functionality is one of the final good features that separates my app from the official Roku app, and I have been trying several methods for a long time to develop this feature. Unfortunately there is no documentation and this is a very complex feature. Additionally there are no 3rd party implementations (open source or otherwise) to rely on to understand the protocol better.

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

## Voice Remote Pro API

-   See [voice-search/VoiceRemotePro/Readme.md](./VoiceRemotePro/Readme.md)

## Roku App API

-   See [voice-search/RokuApp/Readme.md](./RokuApp/Readme.md)
