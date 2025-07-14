# Contributors Guide

This document outlines some of my design philosophy around Roam and some goals I have when making updates to it.

## Goals

1. Keep the binary small and launches fast
    - This is a remote app for goodness sake. If it ever gets above a 6 MB download, I need to revisit size optimizations
2. Keep everything extremely simple, intuitive and foolproof. Onboarding should be smooth and any errors should be presented clearly with the correct fix for them. Reducing the total time spent interacting with our app is the goal.
3. Bring total crashes to zero. Any crash, no matter how weird or rare should be fixed.
4. Roam is very interested in cool and unique features. If there is a feature that the official app implements but nobody else does, we are very interested in making that happen.
5. Accessibility is a key goal. We have several totally-blind users who use this app with screen-reader-only, so we are always working to optimize for accessibility

## How to optimize for size

1. Export a production archive via XCode
2. Open the package in Roam.app/Contents/ and inspect it for unnecessary assets/linked files
3. Inspect the size of the binaries. Because we distribute iOS, watchOS and widgets for each, small binary changes can have a 4x effect on downloads for some users.
    - Run `bloaty -d compileunits --debug-file='Export.xcarchive/dSYMs/Roam.app.dSYM/Contents/Resources/DWARF/Roam' 'Export.xcarchive/Products/Applications/Roam.app/Contents/MacOS/Roam' -d sections,compileunits -n 80` to see the top 80 files by how large their contribution to the binary is
4. Always avoid 3rd party packages like the plague. If you can, vendor the files that you use. If you can't vendor individual files, consider another solution. Currently my only two non-vendored dependencies are libwebp so watchOS can support some webp RokuTV icons and Opus codec for headphones mode, but I am considering dropping libwebp in favor of decoding these files on the backend.
