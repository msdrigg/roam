//
// AttestRepositoryImpl - Roku Mobile Attestation API Repository
// Handles challenge requests, device registration, and attestation flows
//

package ch;

import bh.e;
import bh.h;
import com.roku.mobile.attestation.api.AttestApi;
import com.roku.mobile.attestation.data.AttestationRequest;
import com.roku.mobile.attestation.model.ChallengeResponse;
import com.roku.mobile.attestation.model.RegisterResponse;
import dy.x;
import fh.d;
import fh.g;
import java.security.PublicKey;
import kotlin.NoWhenBranchMatchedException;
import kotlin.coroutines.jvm.internal.f;
import px.o;
import tg.c;

public final class b implements a {
    private final AttestApi attestApi;                    // REST API client for attestation endpoints
    private final g integrityTokenHelper;                // Generates integrity/attestation tokens
    private final d attestKeyPairProvider;               // Manages RSA keypairs from Android KeyStore
    private final c analyticsService;                    // Analytics/logging service
    private final cy.a<String> challengeUrlProvider;     // Provides challenge endpoint URL
    private final cy.a<String> registerUrlProvider;      // Provides registration endpoint URL

    public b(AttestApi api, g tokenHelper, d keyProvider, c analytics, 
             cy.a<String> challengeUrl, cy.a<String> registerUrl) {
        x.i(api, "attestApi");
        x.i(tokenHelper, "integrityTokenHelper");
        x.i(keyProvider, "attestKeyPairProvider");
        x.i(analytics, "analyticsService");
        x.i(challengeUrl, "challengeUrl");
        x.i(registerUrl, "registerUrl");
        super();
        this.attestApi = api;
        this.integrityTokenHelper = tokenHelper;
        this.attestKeyPairProvider = keyProvider;
        this.analyticsService = analytics;
        this.challengeUrlProvider = challengeUrl;
        this.registerUrlProvider = registerUrl;
    }

    /**
     * Get challenge from server (basic version)
     * Used for initial challenge requests without context
     */
    public Object getChallengeBasic(kh.a.b requestType, String requestId, tx.d<? super kh.a> continuation) {
        // Analytics: Log challenge request
        h.d(this.analyticsService, "challenge_requested");
        
        // Make API call to get challenge
        AttestApi api = this.attestApi;
        String challengeUrl = (String)this.challengeUrlProvider.invoke();
        
        try {
            Object apiResponse = api.getChallenge(challengeUrl, continuation);
            zo.b response = (zo.b)apiResponse;
            
            if (zo.f.g(response)) {
                // SUCCESS: Parse challenge response
                ChallengeResponse challengeResp = (ChallengeResponse)zo.f.a(response);
                if (challengeResp != null) {
                    String challenge = challengeResp.a();
                    if (challenge != null) {
                        // Analytics: Log successful challenge retrieval
                        c analytics = this.analyticsService;
                        Long expiration = challengeResp.b();
                        h.e(analytics, "challenge_retrieved", expiration);
                        
                        return new kh.a.c(challenge);  // Return challenge wrapped in success type
                    }
                }
                
                // Challenge field missing
                String errorMsg = zo.f.d(response);
                if (errorMsg == null) {
                    errorMsg = "Challenge field not found";
                }
                
                Integer errorCode = zo.f.b(response);
                int code = (errorCode != null) ? errorCode : -101;
                
                h.d(this.analyticsService, "challenge_failed");
                return new kh.a.f.b(errorMsg, kotlin.coroutines.jvm.internal.b.d(code));
                
            } else {
                // API FAILURE
                String errorMsg = zo.f.d(response);
                if (errorMsg == null) {
                    errorMsg = "Challenge API Failed";
                }
                
                Integer errorCode = zo.f.b(response);
                int code = (errorCode != null) ? errorCode : -104;
                
                h.d(this.analyticsService, "challenge_failed");
                return new kh.a.f.b(errorMsg, kotlin.coroutines.jvm.internal.b.d(code));
            }
            
        } catch (Exception e) {
            h.d(this.analyticsService, "challenge_failed");
            return new kh.a.f.b("Challenge request failed: " + e.getMessage(), -999);
        }
    }

    /**
     * Get challenge from server (with context)
     * Used for assertion requests with specific request context
     */
    public Object getChallengeWithContext(kh.a.d assertionData, String clientId, String requestId, 
                                        tx.d<? super kh.a> continuation) {
        // Analytics: Log challenge request with context
        bh.e.e(this.analyticsService, requestId);
        
        // Make API call to get challenge
        AttestApi api = this.attestApi;
        String challengeUrl = (String)this.challengeUrlProvider.invoke();
        
        try {
            Object apiResponse = api.getChallenge(challengeUrl, continuation);
            zo.b response = (zo.b)apiResponse;
            
            if (zo.f.g(response)) {
                // SUCCESS: Parse challenge response
                ChallengeResponse challengeResp = (ChallengeResponse)zo.f.a(response);
                if (challengeResp != null) {
                    String challenge = challengeResp.a();
                    if (challenge != null) {
                        // Analytics: Log successful challenge retrieval
                        c analytics = this.analyticsService;
                        Long expiration = challengeResp.b();
                        bh.e.f(analytics, requestId, expiration);
                        
                        return new kh.a.c(challenge);  // Return challenge wrapped in success type
                    }
                }
                
                // Challenge field missing
                String errorMsg = zo.f.d(response);
                if (errorMsg == null) {
                    errorMsg = "Challenge field not found";
                }
                
                Integer errorCode = zo.f.b(response);
                int code = (errorCode != null) ? errorCode : -101;
                
                bh.e.d(this.analyticsService, requestId, code, errorMsg);
                return new kh.a.f.b(errorMsg, kotlin.coroutines.jvm.internal.b.d(code));
                
            } else {
                // API FAILURE
                String errorMsg = zo.f.d(response);
                if (errorMsg == null) {
                    errorMsg = "Challenge API Failed";
                }
                
                Integer errorCode = zo.f.b(response);
                int code = (errorCode != null) ? errorCode : -104;
                
                bh.e.d(this.analyticsService, requestId, code, errorMsg);
                return new kh.a.f.b(errorMsg, kotlin.coroutines.jvm.internal.b.d(code));
            }
            
        } catch (Exception e) {
            bh.e.d(this.analyticsService, requestId, -999, "Challenge request failed: " + e.getMessage());
            return new kh.a.f.b("Challenge request failed: " + e.getMessage(), -999);
        }
    }

    /**
     * Register device with server using challenge + public key
     * This is the CRITICAL method that sends the RSA public key for attestation
     */
    public Object registerDevice(kh.a.c challengeResponse, String clientId, String requestId, 
                               tx.d<? super kh.a> continuation) {
        try {
            // STEP 1: Get the RSA public key from Android KeyStore
            d keyProvider = this.attestKeyPairProvider;
            Object publicKeyResult = fh.d.i(keyProvider, false, continuation, 1, null);
            
            // STEP 2: Extract and encode the public key
            byte[] publicKeyBytes = ((PublicKey)publicKeyResult).getEncoded();
            x.h(publicKeyBytes, "attestKeyPairProvider.getPublicKey().encoded");
            
            // CRITICAL LINE: This is where the 32-byte vs 294-byte mystery happens!
            // ep.a.e() = Base64 encoding, but what exactly are we encoding?
            String encodedPublicKey = ep.a.e(publicKeyBytes);
            
            // STEP 3: Create attestation request payload
            AttestationRequest attestationRequest = new AttestationRequest(
                clientId,                    // Device/client identifier
                challengeResponse.a(),       // Challenge from server
                encodedPublicKey            // Encoded public key (the mystery 32-byte value!)
            );
            
            // STEP 4: Send registration request to server
            h.d(this.analyticsService, "register_requested");
            
            AttestApi api = this.attestApi;
            String registerUrl = (String)this.registerUrlProvider.invoke();
            Object apiResponse = api.register(registerUrl, attestationRequest, continuation);
            
            // STEP 5: Handle registration response
            zo.b response = (zo.b)apiResponse;
            
            if (zo.f.g(response)) {
                // SUCCESS: Device registered successfully
                c analytics = this.analyticsService;
                RegisterResponse registerResp = (RegisterResponse)zo.f.a(response);
                Long expiration = (registerResp != null) ? registerResp.b() : null;
                
                h.e(analytics, "register_retrieved", expiration);
                
                // Extract registration token and expiration
                String registrationToken = (registerResp != null) ? registerResp.a() : null;
                Long tokenExpiration = (registerResp != null) ? registerResp.b() : null;
                
                return new kh.a.d(registrationToken, tokenExpiration);
                
            } else {
                // FAILURE: Registration rejected
                Integer errorCode = zo.f.b(response);
                
                if (errorCode != null && errorCode == 435) {
                    // Special case: Integrity check failed
                    h.d(this.analyticsService, "register_failed");
                    String errorMsg = zo.f.d(response);
                    if (errorMsg == null) {
                        errorMsg = "Register integrity failed";
                    }
                    return new kh.a.f.a(errorMsg);
                    
                } else {
                    // General registration failure
                    h.d(this.analyticsService, "register_failed");
                    String errorMsg = zo.f.d(response);
                    if (errorMsg == null) {
                        errorMsg = "Register API Failed";
                    }
                    return new kh.a.f.b(errorMsg, zo.f.b(response));
                }
            }
            
        } catch (Exception e) {
            h.d(this.analyticsService, "register_failed");
            return new kh.a.f.b("Registration failed: " + e.getMessage(), -999);
        }
    }

    /**
     * Request assertion (for signed API calls)
     * This gets a challenge and returns it for signing
     */
    public Object requestAssertion(kh.a.d assertionData, String clientId, String requestId, 
                                 tx.d<? super kh.a> continuation) {
        try {
            // Get challenge for this assertion request
            Object challengeResult = this.getChallengeWithContext(assertionData, clientId, requestId, continuation);
            
            kh.a challengeResponse = (kh.a)challengeResult;
            if (challengeResponse instanceof kh.a.c) {
                // Successfully got challenge, convert to assertion response
                return new kh.a.g(((kh.a.c)challengeResponse).a());
            }
            
            // Return error as-is
            return challengeResponse;
            
        } catch (Exception e) {
            return new kh.a.f.b("Assertion request failed: " + e.getMessage(), -999);
        }
    }

    /**
     * Request attestation (full flow with integrity token)
     * This is the complete flow: challenge -> integrity token -> registration
     */
    public Object requestAttestation(kh.a.b requestType, String requestId, tx.d<? super kh.a> continuation) {
        try {
            // STEP 1: Get challenge from server
            Object challengeResult = this.getChallengeBasic(requestType, requestId, continuation);
            
            kh.a challengeResponse = (kh.a)challengeResult;
            if (!(challengeResponse instanceof kh.a.c)) {
                // Challenge failed, return error
                return challengeResponse;
            }
            
            // STEP 2: Generate integrity token using the challenge
            g tokenHelper = this.integrityTokenHelper;
            String challenge = ((kh.a.c)challengeResponse).a();
            Object tokenResult = tokenHelper.h(challenge, continuation);
            
            g.b tokenResponse = (g.b)tokenResult;
            
            if (tokenResponse instanceof g.b.a) {
                // Integrity token generation failed
                return new kh.a.a.b(((g.b.a)tokenResponse).a());
                
            } else if (tokenResponse instanceof g.b.b) {
                // SUCCESS: Got integrity token, now register device
                kh.a.c challengeData = (kh.a.c)challengeResponse;
                String integrityToken = ((g.b.b)tokenResponse).a();
                
                // STEP 3: Register device with challenge + integrity token
                Object registrationResult = this.registerDevice(challengeData, requestId, integrityToken, continuation);
                return registrationResult;
                
            } else {
                throw new NoWhenBranchMatchedException();
            }
            
        } catch (Exception e) {
            return new kh.a.f.b("Attestation request failed: " + e.getMessage(), -999);
        }
    }
}

/*
KEY INSIGHTS FROM THIS READABLE VERSION:

1. REGISTRATION FLOW:
   - getChallengeBasic() → Get challenge from server
   - integrityTokenHelper.h() → Generate integrity/attestation token  
   - registerDevice() → Send public key + challenge + integrity token
   - Server validates and returns registration token

2. ASSERTION FLOW (for ongoing API calls):
   - getChallengeWithContext() → Get challenge for specific request
   - Client signs request with private key (in gh.a)
   - Server verifies signature using registered public key

3. THE 32-BYTE MYSTERY:
   - Line: String encodedPublicKey = ep.a.e(publicKeyBytes);
   - publicKeyBytes comes from publicKey.getEncoded() (should be ~294 bytes)
   - But real requests show 32-byte clientKey
   - Something is processing the public key before ep.a.e() encoding!

4. ERROR CODES:
   - 435: "Register integrity failed" (special integrity check)
   - -101: "Challenge field not found"  
   - -104: "Challenge API Failed"
   - -999: General exceptions

5. ANALYTICS EVENTS:
   - "challenge_requested" / "challenge_retrieved" / "challenge_failed"
   - "register_requested" / "register_retrieved" / "register_failed"

The mystery is still in that ep.a.e(publicKeyBytes) line - something is transforming
the 294-byte RSA DER into a 32-byte value before Base64 encoding!
*/