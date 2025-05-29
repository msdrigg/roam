# Roku Voice Service

-   I was provided a capture of voice-service.voice.roku.com interacting with the Roku App by a helpful contributor, and I did some analysis of it here.
-   It wasn't a standard pcap file, so I wrote a parser to parse it and write a pcap file to be analyzable in wireshark.
-   I am not going to commit either the capture or the parsed data because it is the private data of the contributor, but I will include the analysis notes here

## Notes

1. Data is HTTPS and HTTP2 encoded and sent to the server in multiple streams
2. There are 2 core streams in the HTTP2 data. One sends audio and configuration (from the Roku app) and the other sends events (from the server). There are some other streams, but they seem to just be for unrelated metrics/reports that probably aren’t necessary to implement.
3. It seems like all streams from the device contain a JWT authorization token (likely used for parsing) as well as several other identifiers in the HTTP2 headers. I don’t know how to get this authorization token and if the other identifiers need to match it, but it is likely generated on the server and present in the traffic in some previous requests, once I get a capture of more of the traffic, that token is likely generated from some endpoint.
4. Interestingly enough, the audio is sent in raw PCM format, so no compression or encryption of any kind. If we can figure out the authentication part, it will likely be very straightforward to replicate this API.
5. This API connects very well to the research I did because I am seeing the traffic from the app to the TV that it looks like is generated on the server here (not on the device). This is interesting, because I thought to replicate this API, it would be necessary to build some kind of voice-recognition/machine learning model. But it looks like we just need to implement this API somehow.

## Next Steps

1. Figure out how to authenticate to the API
2. Write a simple API client to send data to the server and see if I can get intents back.
