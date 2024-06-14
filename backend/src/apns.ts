export type APNSAuthKey = {
    keyId: string;
    teamId: string;
    privateKey: string; // Provide in PEM format
};

function decodeBase64(base64: string): ArrayBuffer {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes = [];

    let i = 0, bin = 0, shift = 0;
    for (let char of base64.replace(/=+$/, '')) {
        bin = (bin << 6) | chars.indexOf(char);
        shift += 6;
        if (shift >= 8) {
            shift -= 8;
            bytes.push(bin >> shift);
            bin &= (1 << shift) - 1;
        }
    }

    return new Uint8Array(bytes).buffer;
}

function encodeBase64(data: ArrayBuffer | string): string {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    if (typeof data === 'string') {
        data = new TextEncoder().encode(data).buffer;
    }

    let bytes = new Uint8Array(data);
    let base64 = '';
    let bin = 0, shift = 0;

    for (let byte of bytes) {
        bin = (bin << 8) | byte;
        shift += 8;
        while (shift >= 6) {
            shift -= 6;
            base64 += chars[(bin >> shift) & 63];
        }
    }

    if (shift > 0) {
        base64 += chars[(bin << (6 - shift)) & 63];
    }

    while (base64.length % 4 !== 0) {
        base64 += '=';
    }

    return base64;
}

async function createJwt(key: APNSAuthKey, algorithm = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" }) {
    // Prepare the signing key from the provided P8 private key
    let privateKeyText = new TextDecoder().decode(decodeBase64(key.privateKey));
    const ecPrivateKey = await crypto.subtle.importKey(
        'pkcs8',
        decodeBase64(privateKeyText.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\n/g, '')),
        algorithm,
        false,
        ['sign']
    );

    // Define JWT Header
    const header = {
        alg: 'ES256',
        kid: key.keyId
    };

    // Define JWT Payload
    const timeNow = Math.floor(Date.now() / 1000);
    const payload = {
        iss: key.teamId,
        iat: timeNow,
        exp: timeNow + 3600
    };

    const toUrlBase64 = (text: string) => encodeBase64(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    const encodedHeader = toUrlBase64(JSON.stringify(header));
    const encodedPayload = toUrlBase64(JSON.stringify(payload));
    const signTarget = `${encodedHeader}.${encodedPayload}`;

    // Sign the Token
    const signature = await crypto.subtle.sign(
        algorithm,
        ecPrivateKey,
        new TextEncoder().encode(signTarget)
    );

    // Return the complete JWT
    return `${signTarget}.${encodeBase64(signature).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')}`;
}

export async function sendPushNotification(title: string, body: string, key: APNSAuthKey, deviceToken: string, bundleId: string) {
    const jwt = await createJwt(key);
    const payload = JSON.stringify({
        aps: {
            alert: {
                title: title,
                body: body
            },
            sound: "default",
            category: "DEVELOPER_RESPONSE"
        }
    });

    const response = await fetch(`https://api.push.apple.com/3/device/${deviceToken}`, {
        method: 'POST',
        headers: {
            'authorization': `bearer ${jwt}`,
            'apns-topic': bundleId,
            'content-type': 'application/json'
        },
        body: payload
    });

    if (!response.ok) {
        const errorData = await response.text();
        throw new Error(`Failed to send push notification: ${errorData}`);
    }

    await sendBackgroundPushNotification(key, deviceToken, bundleId);

    console.log('Push notification sent successfully!');
}

export async function sendBackgroundPushNotification(key: APNSAuthKey, deviceToken: string, bundleId: string) {
    const jwt = await createJwt(key);
    console.log("JWT: ", jwt)
    const payload = JSON.stringify({
        aps: {
            "content-available": 1
        }
    });

    const response = await fetch(`https://api.push.apple.com/3/device/${deviceToken}`, {
        method: 'POST',
        headers: {
            'authorization': `bearer ${jwt}`,
            'apns-topic': bundleId,
            'content-type': 'application/json', 'apns-push-type': 'background',
            'apns-priority': '5',
            'apns-expiration': '0'

        },
        body: payload
    });

    if (!response.ok) {
        const errorData = await response.text();
        throw new Error(`Failed to send background push notification: ${errorData}`);
    }

    console.log('Background push notification sent successfully!');
}
