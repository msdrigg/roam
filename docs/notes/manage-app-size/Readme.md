# Reduce app size

Currently my app is creeping up on 7.5mb when it was initially 5mb. I would like to keep this in mind and develop protocols for how to manage this

## Inspecting app contents

-   Nothing stands out as big. The biggest is the binary size at 5mb and the localizations at 0.3 mb (compressed)
-   Watch App and Widgets binary also add a few megabytes each
-   Assets are only a few mb

## Inspecting the binary

For the macOS version, run the archive build and then right click on the archive in the xcode organizer and click "Show in finder" to get the path to the export.xcarchive

```sh
bloaty -d compileunits --debug-file='Export.xcarchive/dSYMs/Roam.app.dSYM/Contents/Resources/DWARF/Roam' 'Export.xcarchive/Products/Applications/Roam.app/Contents/MacOS/Roam' -n 0
```

Investigate if there's anything we can do to reduce this, find any common patterns, any code we can remove
