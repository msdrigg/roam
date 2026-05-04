# Headphones Mode Debug Scripts

Snippets for capturing and inspecting the RTP/RTCP traffic exchanged with the
Roku TV when headphones mode is active. The Roku in these examples is at
`192.168.10.242` and the Mac is on `en0`; substitute your own values.

The protocol described here is documented in [`audio-protocol.md`](audio-protocol.md).

## 1. Capture

Capture every UDP packet between the Mac and the Roku on the RTP and RTCP
ports. Run this in a terminal *before* enabling headphones mode in the app, then
stop it with Ctrl-C after a few seconds of audio.

```bash
sudo tshark -i en0 \
  -f "host 192.168.10.242 and udp portrange 6970-6971" \
  -w /tmp/roam-headphones.pcap
```

Notes

- `sudo` is required: BPF capture on macOS needs root unless you have already
  granted ChmodBPF / Wireshark capture permissions.
- `udp portrange 6970-6971` covers RTP (6970) and the conventional
  `RTP_port + 1` for RTCP (6971). If the Roku advertises a non-default RTCP
  port, capture both ends with
  `udp port 6970 or udp port 6971 or udp port <remote-rtcp>`.
- Picks the right interface: `tshark -D` lists interfaces. On Wi-Fi networks
  many Roku TVs are joined to a 5 GHz SSID — make sure your Mac is on the same
  segment, otherwise `host 192.168.10.242` matches nothing.

## 2. Quick sanity check on the capture

Print one line per packet. Useful to confirm RTP is flowing and RTCP is
bidirectional.

```bash
tshark -r /tmp/roam-headphones.pcap \
  -o "rtp.heuristic_rtp:TRUE" \
  -d "udp.port==6970,rtp" \
  -d "udp.port==6971,rtcp"
```

Expected pattern

- A burst of small packets to UDP/6971 (the RTCP handshake: VDLY, CVER, RR).
- A continuous flow of ~80–200 byte UDP packets to UDP/6970 every 10 ms once
  audio starts; that's the Opus stream.

## 3. RTP stream summary

Decode RTP and dump per-packet sequence numbers, timestamps, and payload
type. This is the fastest way to see if packets are being lost on the wire vs.
inside the app.

```bash
tshark -r /tmp/roam-headphones.pcap \
  -d "udp.port==6970,rtp" \
  -Y "rtp" \
  -T fields \
    -e frame.time_relative \
    -e ip.src \
    -e rtp.seq \
    -e rtp.timestamp \
    -e rtp.p_type \
    -e rtp.ssrc \
  | head -30
```

What to look for

- `rtp.p_type` should be `97` for Opus on this protocol.
- `rtp.ssrc` should be `0` (the Roam client expects this).
- `rtp.seq` should increase by 1 per packet, with no gaps. Wireshark also
  flags loss directly: `Telephony → RTP → RTP Streams → Analyze`.

## 4. RTCP APP-packet inspection

The Roku handshake (`VDLY` → `XDLY`, `CVER` → `NCLI`) lives in RTCP APP packets
(PT 204). Confirming the round trip in a capture is the easiest way to tell
whether the handshake genuinely completed or whether the client bailed out
early (see the AsyncStream discussion below).

```bash
tshark -r /tmp/roam-headphones.pcap \
  -d "udp.port==6971,rtcp" \
  -Y "rtcp.pt == 204" \
  -V \
  | grep -E "Source: |Destination: |Application:|Name:|Application specific data" -A1
```

The 4-byte ASCII name is at offset 8 inside the APP body
(SSRC then name): `VDLY`, `XDLY`, `CVER`, `NCLI`. Application-specific data
follows for VDLY/XDLY/CVER (32-bit big-endian: microseconds for
VDLY/XDLY, version for CVER); NCLI is empty.

If you only see VDLY going *out* and nothing coming back, the Roku isn't
responding (network/port issue). If you see XDLY coming back but the app log
never says "Got good xdly packet from rtcp as expected", that's the
client-side AsyncStream bug.

## 5. Extract the Opus payload to a raw file

To replay or feed into a different decoder, extract the RTP payload bytes.

```bash
tshark -r /tmp/roam-headphones.pcap \
  -d "udp.port==6970,rtp" \
  -Y "rtp and rtp.p_type == 97" \
  -T fields -e rtp.payload \
  | tr -d ':\n' \
  | xxd -r -p \
  > /tmp/roam-opus.raw
```

`/tmp/roam-opus.raw` is a *concatenation of bare Opus packets* — there's no
container, no length prefixes, and no timing information. To play it back, the
easiest path is to re-wrap it into an Ogg/Opus file with a known frame size
(10 ms in this protocol, so 480 samples at 48 kHz).

A stub script that wraps the captured packets as Ogg/Opus (requires
`opusenc` / a small Ogg muxer; Wireshark also has a built-in
`Telephony → RTP → RTP Player` that will play directly without exporting):

```bash
# Easier alternative: open /tmp/roam-headphones.pcap in Wireshark.app,
# then Telephony → RTP → RTP Streams → Play Streams.
open /tmp/roam-headphones.pcap
```

## 6. Live decode without a capture file

If you just want to watch sequence numbers in real time while the app is
running:

```bash
sudo tshark -i en0 \
  -f "host 192.168.10.242 and udp port 6970" \
  -d "udp.port==6970,rtp" \
  -T fields -e rtp.seq -e rtp.p_type
```

Pair this with the `Received packet in stream (every 1000 packets)` log line
from the app. If tshark's `rtp.seq` advances but the app counter doesn't, the
app's listener isn't reading them. If both advance together but you hear no
audio, the bug is downstream of `RTPSession.streamAudio` (decoder, scheduler,
or AVAudioEngine).

## 7. Sanity-check that the right local ports are bound

```bash
lsof -nP -iUDP:6970 -iUDP:6971
```

While headphones mode is active you should see `Roam` (or your Xcode-run
process) listening on both 6970 and 6971. If you see the same process bound
twice to 6970, that's the old port-mismatch bug
(`requiredLocalEndpoint` using the RTP port for the outbound RTCP socket) and
matches the kernel `[17: File exists]` log.

## Notes / gotchas

- macOS Wi-Fi can drop to monitor mode silently while sniffing; if RTP suddenly
  stops appearing in tshark but the TV says audio is still routing, just stop
  and restart the capture.
- The RTCP listener and the outbound RTCP connection both use UDP port 6971
  after the recent fix. Wireshark will show both directions on the same UDP
  flow, which is correct.
- The app currently sends RTCP BYE only on listener teardown. If you kill the
  app abruptly the Roku may keep streaming for several seconds before timing
  out on its own.
