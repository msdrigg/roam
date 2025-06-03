```
curl -X POST "https://auth.prod.mobile.roku.com/identity/register" \
  -H "x-roku-reserved-lat: true" \
  -H "x-roku-reserved-request-id: BFA0C167-9848-4053-9340-CF3EC206536D" \
  -H "x-roku-reserved-rida: " \
  -H "profile-id-is-uuid: true" \
  -H "x-roku-reserved-amoeba-ids: " \
  -H "x-roku-reserved-dev-id: 1a2f5fd09622fd2b68be13fff92f09aebb6837fd" \
  -H "x-roku-reserved-profile-id: 43E88A66-385E-4FB2-BFF8-4A026A880624" \
  -H "appversion: 12.6.0" \
  -H "x-roku-reserved-mobile-experiment-ids: " \
  -H "x-roku-reserved-channel-store-code: us" \
  -H "x-roku-reserved-client-id: 6E14E7A3-E277-48E1-9C05-7E59D96DA9F8" \
  -H "x-roku-reserved-culture-code: en_MX" \
  -H "version: 2.0" \
  -H "os: ios" \
  -H "x-roku-reserved-correlation: mob_727852BC-0299-49E9-B397-A120650A5938" \
  -H "x-roku-reserved-locale: en_MX" \
  -H "x-roku-reserved-client-version: app=turing, appversion=12.6.0, os=ios, platform=mobile, version=2.0" \
  -H "x-roku-reserved-session-id: 6F434D28-057E-4D52-B5FC-6900D9917DBC" \
  -H "osVersion: 15.8.2" \
  -H "Content-Type: application/json" \
  -H "x-roku-reserved-time-zone-offset: +01:00" \
  -H "app: remote"

>>> {"apiVersion":"1"}
```

```
curl https://auth.prod.mobile.roku.com/client/6E14E7A3-E277-48E1-9C05-7E59D96DA9F8/challenge
>>>{"apiVersion":"1","data":{"challenge":"e22b7256a6b2435f9a5f986fd4592700","exp":1748888647,"ttl":300}}%
```

```
curl -X POST "https://auth.prod.mobile.roku.com/client/6E14E7A3-E277-48E1-9C05-7E59D96DA9F8/register" \
  -H "app: remote" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "os: ios" \
  -H "appversion: 12.6.0" \
  -d '{
    "challenge": "b149bae5dd0741bfb45f6eac2b7fc3bb",
    "clientKey": "eCV+JVRGEywPyB9O0JlG+fr1Vk/sPjQTSpwE0dphoAU=",
    "attestationResult": "<How to get this value?>",
    }'
```

```
curl -X POST "https://account.prod.mobile.roku.com/v1/token?assert=true" \
  -H "x-roku-reserved-lat: true" \
  -H "x-roku-reserved-request-id: 1CBE0B73-EBA9-43AA-BF4D-0A7FA3849032" \
  -H "assertion-signature: signed_headers=app;appversion;assertion-challenge;assertion-request-ts;content-type;host;os;osversion;profile-id-is-uuid;version;x-roku-reserved-amoeba-ids;x-roku-reserved-channel-store-code;x-roku-reserved-client-id;x-roku-reserved-client-version;x-roku-reserved-correlation;x-roku-reserved-culture-code;x-roku-reserved-dev-id;x-roku-reserved-lat;x-roku-reserved-locale;x-roku-reserved-mobile-experiment-ids;x-roku-reserved-profile-id;x-roku-reserved-request-id;x-roku-reserved-rida;x-roku-reserved-session-id;x-roku-reserved-time-zone-offset, hash_alg=HMAC_SHA256, client_id=6E14E7A3-E277-48E1-9C05-7E59D96DA9F8, salt=omlzaWduYXR1cmVYRzBFAiEAq8NIm+FCWpJr/AvsSc77YN3zCqk5k1nQnr4mjQ5g9c4CIFmnzUvZFlTlVsauztEVLBupHDdoDC6JFZI8hAtRmaCZcWF1dGhlbnRpY2F0b3JEYXRhWCXzW0GIcWvGxWxVGT3IPhgp1tU1kB/pgE6WylqQpkbF6EAAAAAC, signature=omlzaWduYXR1cmVYRzBFAiEA4d8OS/D3BIqyvDFe/abqFl5hJbFQWeHYtHFXae7a8asCIBoDYlwDd2SKGIJJto4DUxNd2wwsjVzE1/qt0HB7b3zGcWF1dGhlbnRpY2F0b3JEYXRhWCXzW0GIcWvGxWxVGT3IPhgp1tU1kB/pgE6WylqQpkbF6EAAAAAB" \
  -H "Host: account.prod.mobile.roku.com" \
  -H "profile-id-is-uuid: true" \
  -H "x-roku-reserved-dev-id: 1a2f5fd09622fd2b68be13fff92f09aebb6837fd" \
  -H "x-roku-reserved-rida: " \
  -H "x-roku-reserved-amoeba-ids: " \
  -H "x-roku-reserved-client-id: 6E14E7A3-E277-48E1-9C05-7E59D96DA9F8" \
  -H "appversion: 12.6.0" \
  -H "x-roku-reserved-mobile-experiment-ids: " \
  -H "x-roku-reserved-channel-store-code: SOME" \
  -H "x-roku-reserved-profile-id: 43E88A66-385E-4FB2-BFF8-4A026A880624" \
  -H "assertion-request-ts: 1748873408.977489" \
  -H "x-roku-reserved-culture-code: en_MX" \
  -H "version: 2.0" \
  -H "os: ios" \
  -H "x-roku-reserved-correlation: mob_38A83FA8-ED0D-42F5-8101-F8B3570A95B1" \
  -H "x-roku-reserved-locale: en_MX" \
  -H "x-roku-reserved-client-version: app=turing, appversion=12.6.0, os=ios, platform=mobile, version=2.0" \
  -H "x-roku-reserved-session-id: 6F434D28-057E-4D52-B5FC-6900D9917DBC" \
  -H "assertion-challenge: aedbbe27f76f4eed98e07821b81fe7b5" \
  -H "osVersion: 15.8.2" \
  -H "Content-Type: application/json" \
  -H "x-roku-reserved-time-zone-offset: SOME" \
  -H "app: remote" \
  -d '{"tokenType": ["JWT"]}'
```
