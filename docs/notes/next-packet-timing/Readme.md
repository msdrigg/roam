# NextPacket Timing

Our RTP Audio stream is currently under-performing and can get stuck in a bad state where it thinks that the packets it's receiving are out-of-order or in a bad state. I need to rewrite this handling to account for imprecise timing in the loop function call and instead rely on the jitter buffer to handle this correctly + my own timing calculations to know how many packets to schedule and for when

## How this should work

-   Ideally we have two independent loops
    -   One loop that loops on receive packets and adds each packet to the jitter buffer
    -   Another loop that loops and calculates which packet(s) to pull off the jitter buffer and schedule onto the audio thread
-   Need to figure out a way to track when to schedule audio on the audio thread
    -   Input variables include
        -   Output Latency (Determined by LatencyListener)
        -   Network Latency (Need a better calculation through RTCP)
            -   Calculate through EMA
        -   Video Delay (VDLY, Constant)
    -   Need to perform all calculations in a frame and packet-aware way. Each packet contains a dedicated number of frames, and each frame needs to be played after the previous frame perfectly
        -   Need there to be a function of all input variables that takes sequence number (seqNo) and outputs frame number
        -   Need to ensure when popping the packet off that it is played exactly after the last packet that was popped (or play a loss concealment)
        -   Need to ensure that when network or output latency is updated that we handle the change gracefully
            -   For skipping forward, just re-set the sync between frame counter and audio frame number. There will be a bit of dead air but that's OK
            -   For skipping backward, need to interrupt the current audio (set .interrupt audio playback option). A bit of playback will be missed but that's OK
    -   Schedule with scheduleAvailableAudio
        -   Internal while loop for multiple-packet-decode scenario
    -   I should consider building these into NWProtocolFramer's
        -   Incorporate jitter buffer, opus decoder into a NWProtocolFramer
            -   Output is raw video packet frames
        -   Incorporate RTCP protocol into a separate one
            -   Output is RTCP round trip reports
-   Need to ensure that my program performs well under shitty network conditions
    -   Need to test with a variable and high network latency
    -   Need to test with variable and high packet loss
    -   Test with quickly changing output latency
    -   Need to compare with current roam application version (main branch)
    -   Need to compare with LibSAS (official remote)
    -   Need to compare with Datagram (official remote)

## Testing Notes

-   Network conditioning for testing can be done with Apple's Network Link Conditioner
    -   [install from 'additional tools for xcode'](https://developer.apple.com/download/all/?q=network%20link%20conditioner)
-   Network conditioning can be done at the router/interface level with a router in the middle using `tc` for more fully featured or complex scenarios
    -   [tc-netem](https://man7.org/linux/man-pages/man8/tc-netem.8.html)
    -   `tc qdisc [replace|add] dev br-lan root netem loss gemodel 2% 20% 95% 1%`
    -   `tc qdisc add dev br-lan root netem loss 10%`
    -   `tc qdisc add dev br-lan root netem delay 100ms loss 5% duplicate 1% corrupt 0.1%` (combine multiple)
-   Need to have statics available for what percent of packets played out of jitter buffer, what percent are dropped after receiving, and what percent are reordered
