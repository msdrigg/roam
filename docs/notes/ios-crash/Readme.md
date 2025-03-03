# iOS Crash Report

iOS Roam closes unexpectedly when opened from a backgrounds state (closed but not force closed). I am unable to get any good logs off of it, and the reproduction is finicky. It also rarely/never occurs when the app is in debug mode, so running it from xcode is tricky

My in-app log capture only captures logs from the current process run (not before the crash), so I don't have any information from it about pre-crash events

I also have seen that it appears my app is exiting with exit(0) so there's no crash reported. I added atexit to my main app so hopefully I will see a crash if it's truly exiting with exit(0). But idk.

## Things I figured out

-   SIGPIPE crash reason (13) was the key
-   Apps crash with SIGPIPE and don't produce a crash report when writing to a broken pipe or a broken socket. It looks like sockets are my problem.
-   Tentatively solved with using setsocketopt no_sigpipe (https://developer.apple.com/forums/thread/773307)

## Next Steps

-   Writup post with this fix
