# Roku Voice Service

-   I was provided a capture of voice-service.voice.roku.com interacting with the Roku App by a helpful contributor, and I did some analysis of it here.
-   It wasn't a standard pcap file, so I wrote a parser to parse it and write a pcap file to be analyzable in wireshark.
-   I am not going to commit either the capture or the parsed data because it is the private data of the contributor, but I will include the analysis notes here

## 05-25-2025

### Notes

1. Data is HTTPS and HTTP2 encoded and sent to the server in multiple streams
2. There are 2 core streams in the HTTP2 data. One sends audio and configuration (from the Roku app) and the other sends events (from the server). There are some other streams, but they seem to just be for unrelated metrics/reports that probably aren’t necessary to implement.
3. It seems like all streams from the device contain a JWT authorization token (likely used for parsing) as well as several other identifiers in the HTTP2 headers. I don’t know how to get this authorization token and if the other identifiers need to match it, but it is likely generated on the server and present in the traffic in some previous requests, once I get a capture of more of the traffic, that token is likely generated from some endpoint.
4. Interestingly enough, the audio is sent in raw PCM format, so no compression or encryption of any kind. If we can figure out the authentication part, it will likely be very straightforward to replicate this API.
5. This API connects very well to the research I did because I am seeing the traffic from the app to the TV that it looks like is generated on the server here (not on the device). This is interesting, because I thought to replicate this API, it would be necessary to build some kind of voice-recognition/machine learning model. But it looks like we just need to implement this API somehow.

### Analyzing Auth

-   Need to find a way to perform the analysis to figure out how the in-app signature occurs. There is some kind of secret signature scheme that we need to figure out to make this work. This was always expected, but we'll see if we can crack it.

### Next Steps

0. Figure out how to jailbreak and intercept traffic from my device
    - https://andydavies.me/blog/2019/12/12/capturing-and-decrypting-https-traffic-from-ios-apps/
    - https://github.com/doronz88/harlogger
1. Figure out how to authenticate to the API
2. Write a simple API client to send data to the server and see if I can get intents back.

## 06-01-2025

-   Auth on iOS is uncrackable. It uses DeviceCheck API to do an attestation that 1. it's running on apple hardware and 2. it's running on the <team_id>.com.roku.remote app, so we can't do this. You can verify that it uses this by running parse-cbor.py to see that the attestationResult parameter in the device register request matches the format of apple's device attestation.
-   Auth on Android (see auth/decompiled-android) looked like it _could_ be crackable, but it's not going to be possible to check on it without a packet capture. I see that the attestation bit was set in the crypto, but it's not clear they export the full cert chain (it looks like just the pub key). I would want a full export to really see for sure.
-   But I am thinking that it's very possible that the TV's internal system uses this same auth API. I would want to search for some of the json strings from the configuration_v2 package to see if I can find them in the firmware dump. If they are assuming the TV can be trusted, it's possible that the API is less locked down. But it's possible they lock down the API in other ways (verifying serial number is valid, etc.). If this is the case, we may be stuck with homegrown-ml or roku-voice-pro options.
