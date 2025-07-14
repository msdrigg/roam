## AI Notes

Looking at this decompiled `gh.a` class, I can definitely see signing code! This appears to be an attestation signing implementation. Here are the key signing-related methods I've identified:

## Main Signing Methods

**1. `j()` method - "createSignedRequest"**

-   This is the main method that creates a signed request
-   It builds specific headers like `assertion-challenge`, `assertion-request-ts`, `apiweb-env`, etc.
-   Gets a `PrivateKey` from `this.c.g(var20, var16)`
-   Creates an `assertion-signature` header with components like:
    -   `hash_alg=HMAC_SHA256`
    -   `client_id=...`
    -   `signed_headers=...`
    -   `signature=...`
    -   `salt=...`

**2. `p()` method - "prepareSignedPayload"**

-   Creates a canonical request string including HTTP method, URL, headers, and body
-   Calls `this.o()` to prepare the string to be signed
-   Uses `ep.a.d()` to perform the actual signing with the private key
-   Returns the signature

**3. `o()` method - Creates the signing payload**

-   Builds a string containing:
    -   `"HMAC_SHA256"` (the algorithm)
    -   Timestamp, client ID, and other parameters
    -   This becomes the payload that gets signed

## Key Observations

-   **Algorithm**: Uses HMAC-SHA256 for signing
-   **Headers signed**: Includes specific headers like `assertion-challenge`, `host`, `apiweb-env`, etc.
-   **Salt**: Uses "roku" as a salt value
-   **Private Key**: Retrieved from `this.c` (which appears to be an `attestKeyPairProvider`)

## Where to Look Next

The actual cryptographic operations are handled by the **`ep.a` class**, which isn't shown here. You should look for:

1. **`ep.a.d()`** - This appears to be the actual signing function
2. **`ep.a.e()`** - Likely base64 encoding
3. **`ep.a.a()`** - Possibly SHA-256 hashing
4. **`d` class** (the `attestKeyPairProvider`) - Manages the private keys used for signing

The signing flow is: `m()` → `j()` → `p()` → actual crypto in `ep.a` class.
