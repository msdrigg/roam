# In-TV Audio (ECP-Voice)

So the Roku TV seems to have some endpoints that could allow in-tv audio. Any request POST request sent to `/voice/*` returns `204 No Content` instead of the typical 404 response. I think the main endpoints of interest are the following

```
/voice/audio
/voice/events
/voice/dictation
/voice/intent
/voice/inject
```

The first 4 because those are the endpoints used for the main app to get the audio (e.g. `POST https://voice-service.voice.roku.com/api/1.0/voice/audio`), and the last one because I saw it referenced within a directory in the roku firmware dump.

The firmware dump seemed to indicate that json could be sent like this, but I couldn't get any kind of response from my TV on this.

```
curl -X POST -vvv http://192.168.8.242:8060/voice/inject?intent=<uriEncodedJson>
```
