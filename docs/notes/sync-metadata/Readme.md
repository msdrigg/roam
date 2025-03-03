# Sync-Metadata

Currently, sync-metadata is a python script that uses the appstoreconnect api to upload description and changelog to the app store

## Programatic Screenshot

-   Programatic screenshot is implemented with XCTest

## Next Steps

-   Automatically run xctest with the sync-metadata script and extract screenshots from the build with xcparse (or whatever that tool is called)
-   Automatically upload the screenshots to the app store matching the localization
-   Embed the screenshots into an HTML + CSS document for better app store presentation and then export to the properly sized image using
    -   Write out the templates (see examples in ./AppStoreExamples)
    -   Use playwrite + python bindings to do the rendering
-   Make sure to build out screenshots to highlight key features
    -   Simple and intuitive design
    -   Automatic TV Detection
    -   Widgets, shortcuts, control panel widgets
    -   Menu bar item
    -   Cross-platform functionality
    -   Keyboard shortcuts
    -   Automatic text entry
    -   Dedicated support/troubleshooting
    -   Headphones mode
-   Build out a video somehow
    -   Can I pay somebody to design it and then I re-implement it in one of these systems?
        -   Need to review a few videos that I like to come up with an idea for iOS, macOS, iPadOS and Apple Watch
        -   Consider paying someone on
            -   https://contra.com/discover/independents
            -   UpWork
            -   Fiverr
    -   Need to update my xctest to include some video snippets that would be useful for this video
    -   Consider using one of these tools
        -   https://www.remotion.dev/showcase
            -   Not open source and requires payment for companies with more than 3 employees
        -   Revideo (https://re.video/)
            -   Built on motioncanvas, and not as up to date
            -   But it does have headless rendering
        -   Manim community
        -   https://rive.app/experts (for any animations?)
    -   Good video examples
        -   https://apps.apple.com/us/app/cardhop-contacts/id1290358394?mt=12
