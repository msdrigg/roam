# End game notes

This document outlines the end game goals for Roam. Obviously this will be an evolving application but in general here's where I want to go with this app

## Feature Parity

-   Voice Search
    -   In-app voice search that can perform actions on the TV
    -   I think I can make this really functional using a combination of Roku and Apple API's. If I can figure out the Roku API's, then my feature could actually end up better than the official one.
-   Improved Headphones Mode
    -   Currently my headphones mode implementation is based off the legacy RTP protocol, but the later versions of the Roku app use a new proprietary LibSAS which offers better performance and some increased functionality over the legacy protocol (e.g. quicker shutdown when disabling headphones mode). Additionally I'm worried they are going to shut down the old one and render my feature unusable.

## Simplify the User Interaction in the Unhappy Path

-   The happy path is currently very simple but any time there is a connection problem or some system issue, there is a lot of room we have for improvement with the app
-   For example my explanation for why headphones mode/volume control fails means people have no idea when it doesn't work even though I could probably give them a reason.

## Improve the UI

-   The main control buttons are a bit too small/clunky
-   I would like to have a gesture-recognizer for the app
-   I want long-press capabilities on buttons

## Specific Non-features

-   Working with non-roku tv's.
    -   If I want an app to work with other TV's, I will make a different app. This app is Roku specific
-   In-app movie/tv search.
    -   I don't like the official Roku's features of managing an account, searching for movies/tv shows or anything else. It's not what I want this remote to be, so I won't build it
