# iOS Crash Report

iOS Roam closes unexpectedly when opened from a backgrounds state (closed but not force closed). I am unable to get any good logs off of it, and the reproduction is finicky. It also rarely/never occurs when the app is in debug mode, so running it from xcode is tricky

My in-app log capture only captures logs from the current process run (not before the crash), so I don't have any information from it about pre-crash events

I also have seen that it appears my app is exiting with exit(0) so there's no crash reported. I added atexit to my main app so hopefully I will see a crash if it's truly exiting with exit(0). But idk.

## Next Steps

-   Review captured sysdiagnose
-   See if I can attach a debugger to the running project and then open it in xcode while it crashes
-   Review secondary sysdiagnose + jetsam
-   See if current version crashes (without debugger attached...)
-   Wait for response from ios dev forums https://developer.apple.com/forums/thread/773205?login=true
