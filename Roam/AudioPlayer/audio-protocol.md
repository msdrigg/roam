# Roku Headphones Mode Audio Protocol

This describes the protocol as implemented by the Roam client in this directory. It is not an authoritative Roku specification; details below are inferred from the client behavior and should be treated as implementation notes.

## Overview

Headphones mode is started over the existing ECP websocket connection, then audio is delivered over UDP using RTP. A parallel RTCP channel is used for a small proprietary handshake, periodic receiver reports, and shutdown signaling.

The client acts as the RTP receiver:

1. Open local UDP listeners for RTP and RTCP.
2. Send an ECP `set-audio-output` request telling the Roku where to send datagram audio.
3. Perform an RTCP APP-packet handshake.
4. Receive RTP packets containing Opus frames.
5. Decode, jitter-buffer, and schedule audio locally.
6. Send RTCP receiver reports once per second while the session is alive.

## Constants

Current client constants:

| Name | Value | Meaning |
| --- | ---: | --- |
| Local RTP port | `6970` | UDP port where Roam receives audio RTP. |
| Local RTCP port | `6971` | UDP port where Roam listens for RTCP responses from Roku. |
| Default remote RTCP port | `5150` | Roku RTCP port if the device metadata does not advertise one. |
| RTP payload type | `97` | Expected payload type for Opus audio in incoming RTP packets. |
| RTP SSRC | `0` | Expected SSRC in incoming audio packets and used in outgoing RTCP packets. |
| Clock rate | `48000` | Opus/sample clock rate in Hz. |
| Packet size | `10 ms` | Expected duration of each RTP Opus packet. |
| Fixed VDLY value | `600 ms` | Delay value sent in the RTCP delay handshake. |
| Client version | `2` | Value sent in the RTCP `CVER` APP packet. |

The ECP `devname` advertises `host:6970:97:960`, where `960` is `48000 / 50`. This value appears to describe the Opus frame size in samples for 20 ms, even though playback scheduling assumes 10 ms packets. The exact server-side interpretation is not proven by this client.

## Session Setup

The app enters headphones mode by sending a websocket ECP command:

```text
request: set-audio-output
audio-output: datagram
devname: <client-ip>:6970:97:960
```

`<client-ip>` is selected from the local interface used by the current ECP websocket path. The client then expects the Roku to send RTP audio datagrams to `<client-ip>:6970`.

The Roku RTCP address is taken from the device's ECP location URL host. The remote RTCP port comes from `query/audio-device` metadata at `rtp-info/rtcp-port` when available, otherwise it defaults to `5150`. That same audio-device response is also used elsewhere to detect whether `datagram` appears in `capabilities/all-destinations`.

## UDP Channels

### RTP

RTP audio is received on local UDP port `6970`.

The client accepts standard RTP version 2 packets:

```text
0                   1                   2                   3
0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|X|  CC   |M|     PT      |       sequence number         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           timestamp                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                             SSRC                              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|            CSRC list and extension, if present                |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Opus payload                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

Observed/expected RTP fields:

| Field | Expected behavior |
| --- | --- |
| Version | Must be `2`; other versions are rejected. |
| Payload type | Expected to be `97`; other values are logged as invalid. |
| SSRC | Expected to be `0`; other values are logged as invalid. |
| Sequence number | 16-bit RTP sequence number, unwrapped locally into a rolling sequence. |
| Timestamp | Parsed but not currently used for playback timing. |
| Marker | Parsed but not currently used. |
| CSRC/extension/padding | Parsed enough to locate payload. Padding length is validated, but the decoder path currently uses the raw payload slice rather than `payloadWithoutPadding`. |
| Payload | Opus packet data decoded at 48 kHz stereo float PCM. |

Packets older than the current playback sequence are dropped. Missing packets are concealed with Opus packet loss concealment.

### RTCP

RTCP uses UDP in both directions:

| Direction | Endpoint |
| --- | --- |
| Client to Roku | Roku host, advertised RTCP port or default `5150`. |
| Roku to client | Client local RTCP port `6971`. |

The outgoing RTCP connection uses an OS-assigned ephemeral source port — pinning it to `6971` (the listener's port) caused the kernel to deliver any 4-tuple-matching reply to the outbound connection instead of the listener, silently dropping Roku's responses. Incoming RTCP is received on local UDP port `6971`, which matches the conventional RTP port plus one. Roku addresses replies to that port regardless of our source port, so the dedicated listener picks them up cleanly.

The implementation parses RTCP version 2 packets with packet types:

| PT | Name | Client behavior |
| ---: | --- | --- |
| `200` | Sender Report | Parsed as known packet type, body currently ignored. |
| `201` | Receiver Report | The client can emit empty receiver reports. Incoming parsing is not implemented. |
| `203` | BYE | The client can emit BYE with SSRC `0`. Incoming parsing is not implemented. |
| `204` | APP | Used for the proprietary Roku handshake. |

All outgoing RTCP packets use version `2`, no padding, and SSRC `0`.

## RTCP APP Packets

APP packets use RTCP packet type `204`. The body format used by this client is:

```text
0                   1                   2                   3
0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           SSRC = 0                            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       4-byte ASCII name                       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                  application-dependent data                   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

Recognized APP names:

| Name | Direction | Payload | Meaning |
| --- | --- | --- | --- |
| `VDLY` | Client to Roku | 32-bit big-endian delay in microseconds | Client video/audio delay declaration. Roam sends `600000`. |
| `XDLY` | Roku to client | 32-bit big-endian delay in microseconds | Roku acknowledgement of the requested delay. Roam expects exactly `600000`. |
| `CVER` | Client to Roku | 32-bit big-endian client version | Roam sends `2`. |
| `NCLI` | Roku to client | Empty | Roku acknowledgement of the client-version/new-client handshake. |

Unknown APP names are preserved as opaque name plus payload if parsed.

## RTCP Handshake

During session startup, Roam performs this handshake:

1. Send APP `VDLY` with delay `600000` microseconds to the Roku RTCP endpoint.
2. Wait for APP `XDLY`.
3. Accept the `XDLY` only if its delay is exactly `600000` microseconds.
4. Send APP `CVER` with client version `2`.
5. Wait for APP `NCLI`.

Each handshake step is attempted with a one-second timeout and retried until it succeeds or the task is cancelled. The overall startup path wraps the RTCP handshake in a six-second timeout.

Once the handshake succeeds, Roam sends an empty RTCP receiver report every second:

```text
PT = 201
report count = 0
SSRC = 0
no report blocks
```

When local RTCP listener state fails or is cancelled, the client attempts to send RTCP `BYE` with SSRC `0`.

## Audio Format

Incoming RTP payloads are Opus packets decoded as:

| Property | Value |
| --- | --- |
| Sample rate | `48000 Hz` |
| Channels | `2` |
| PCM format after decode | Float32 |

The decoded PCM is converted to the current AVAudioEngine output format before scheduling.

## Jitter Buffer and Timing

Roam uses the first accepted RTP packet as a synchronization reference, though the stream receiver intentionally skips the first four packets before feeding packets into the jitter buffer.

Playback timing is based on local host time and RTP sequence numbers, not RTP timestamps:

1. The client estimates the current packet number from the synchronization packet's receive time, local render time, and expected packet rate.
2. The jitter buffer target is `400 ms`.
3. Packets are scheduled every `10 ms`.
4. Missing packets are replaced with Opus packet loss concealment for the expected sample count.

The scheduling delay is derived from:

```text
additionalAudioDelay = (fixedVDLYMs - baseAudioDelayMs) / 1000 - outputLatency
```

Where:

```text
fixedVDLYMs = 600
baseAudioDelayMs = videoBufferMs + baseAudioTransitMs = 400 + 0
```

So the target additional audio delay before subtracting local output latency is about `200 ms`.

On platforms with latency events, the client resynchronizes when output latency changes.

## Implementation Caveats

- RTP timestamp values are parsed but ignored for audio synchronization.
- RTCP sender reports are accepted but not interpreted.
- Incoming RTCP receiver reports and BYE packets are represented in the model, but their parsers currently return `nil`.
- Incoming RTP packets with unexpected SSRC or payload type are logged, but the current client still inserts them into the jitter buffer if their sequence number is newer.
- The RTCP parser validates packet version and type, but reads and then ignores the RTCP length field.
- The RTCP encoder assumes packet bodies are already 32-bit aligned and does not add padding.
- The ECP `devname` frame-size field is inferred from the client constant expression and may not mean exactly what its value suggests.
