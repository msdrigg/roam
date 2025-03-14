# Gimmiks

This document is a collection of future small changes that could provide a little bit of entertainment or fun for users' lives

## Implement Things3-like min-window-dragging behavior

In the Things3 App (and Paper Editor), the window will drag up and to the right with a decreasing rate as you try to adjust it beyond it's min size

    - I attempted GimmikScalarDelegate (https://github.com/msdrigg/Roam/blob/50a2a641aa5f2fccb4382e14dbb410c1679d8b0c/Roam/GimmikScalarDelegate.swift#L6) to do this, but it doesn't receive the right callbacks
    - I reached otu to Mahhail from Paper Editor and he said to try this:
        - I have overridden setFrame:display: on NSWindow to intercept and adjust the window frame.
        - I am saving the mouse position from NSEvent.mouseLocation at the moment when the min size has been reached.
        - Finally, I am comparing it to the current position from NSEvent.mouseLocation to know what adjustments I need to make to the window frame.
    - Unfortunately I cannot override NSWindow without removing the whole @main portion of my SwiftUI app
        - https://developer.apple.com/forums/thread/775931
