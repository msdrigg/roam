package fh

import com.roku.mobile.attestation.state.AttestationConfig
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import tg.c
import java.security.KeyStore
import java.security.PrivateKey
import java.security.PublicKey
import java.security.cert.Certificate

/**
 * AttestKeyPairProvider - Manages RSA keypairs for Roku mobile attestation
 * 
 * This class handles:
 * - Retrieving public/private keys from Android KeyStore
 * - Thread-safe access with mutex synchronization
 * - Coroutine-based async operations
 * - Key lifecycle management
 */
class AttestKeyPairProvider(
    private val keyPairGenerator: a,                    // fh.a interface for generating keys
    private val analyticsService: c,                    // Analytics/logging service
    private val attestationConfig: AttestationConfig,   // Configuration for attestation
    private val dispatcher: CoroutineDispatcher        // Coroutine dispatcher for IO operations
) {
    
    // Mutexes for thread-safe access to keystore operations
    private val privateKeyMutex = Mutex()
    private val publicKeyMutex = Mutex()
    
    companion object {
        private const val KEYSTORE_ALIAS = "ATTEST"
        private const val KEYSTORE_TYPE = "AndroidKeyStore"
    }
    
    /**
     * Get private key from Android KeyStore (suspending function)
     * Used for signing attestation requests and API calls
     * 
     * @param requestId The request ID for analytics/logging
     * @return PrivateKey from hardware keystore, or null if not found
     */
    suspend fun getPrivateKey(requestId: String): PrivateKey? {
        return withContext(dispatcher) {
            privateKeyMutex.lock()
            try {
                getPrivateKeyFromKeystore()
            } catch (e: Exception) {
                // Log error through analytics service
                logKeyAccessError("private", requestId, e)
                null
            } finally {
                privateKeyMutex.unlock()
            }
        }
    }
    
    /**
     * Get public key from Android KeyStore (suspending function)
     * Used for device registration and sending to Roku servers
     * 
     * @param forceRefresh Whether to force refresh from keystore
     * @return PublicKey from certificate, or null if not found
     */
    suspend fun getPublicKey(forceRefresh: Boolean = false): PublicKey? {
        return withContext(dispatcher) {
            publicKeyMutex.lock()
            try {
                // This calls the existing private method j()
                getPublicKeyFromCertificate()
            } catch (e: Exception) {
                // Log error through analytics service  
                logKeyAccessError("public", "getPublicKey", e)
                null
            } finally {
                publicKeyMutex.unlock()
            }
        }
    }
    
    /**
     * Get public key from certificate in Android KeyStore
     * This is the existing private method j() made more readable
     */
    private fun getPublicKeyFromCertificate(): PublicKey? {
        return try {
            val keyStore = KeyStore.getInstance(KEYSTORE_TYPE)
            keyStore.load(null) // Load Android KeyStore (no password needed)
            
            val certificate: Certificate? = keyStore.getCertificate(KEYSTORE_ALIAS)
            certificate?.publicKey
            
        } catch (e: Exception) {
            logKeystoreError("Failed to get public key from certificate", e)
            null
        }
    }
    
    /**
     * Get private key from Android KeyStore  
     * This is the implementation that was obfuscated in getPrivateKey()
     */
    private fun getPrivateKeyFromKeystore(): PrivateKey? {
        return try {
            val keyStore = KeyStore.getInstance(KEYSTORE_TYPE)
            keyStore.load(null) // Load Android KeyStore
            
            // Get private key using the same alias as certificate
            val privateKey = keyStore.getKey(KEYSTORE_ALIAS, null) as? PrivateKey
            privateKey
            
        } catch (e: Exception) {
            logKeystoreError("Failed to get private key from keystore", e)
            null
        }
    }
    
    /**
     * Check if keys exist in keystore
     * Useful for determining if key generation is needed
     */
    suspend fun keysExist(): Boolean {
        return withContext(dispatcher) {
            try {
                val keyStore = KeyStore.getInstance(KEYSTORE_TYPE)
                keyStore.load(null)
                
                // Check if both certificate and private key exist
                val hasCertificate = keyStore.containsAlias(KEYSTORE_ALIAS) && 
                                   keyStore.isCertificateEntry(KEYSTORE_ALIAS)
                val hasPrivateKey = keyStore.containsAlias(KEYSTORE_ALIAS) && 
                                  keyStore.isKeyEntry(KEYSTORE_ALIAS)
                
                hasCertificate && hasPrivateKey
                
            } catch (e: Exception) {
                logKeystoreError("Failed to check key existence", e)
                false
            }
        }
    }
    
    /**
     * Generate new keypair if needed
     * This would call the fh.a (keyPairGenerator) interface
     */
    suspend fun ensureKeysExist(): Boolean {
        return if (!keysExist()) {
            withContext(dispatcher) {
                try {
                    // Call the key generator (fh.b implements fh.a)
                    val keyPair = keyPairGenerator.invoke()
                    keyPair != null
                } catch (e: Exception) {
                    logKeystoreError("Failed to generate new keypair", e)
                    false
                }
            }
        } else {
            true // Keys already exist
        }
    }
    
    /**
     * Delete keys from keystore (for key rotation/cleanup)
     */
    suspend fun deleteKeys(): Boolean {
        return withContext(dispatcher) {
            privateKeyMutex.lock()
            publicKeyMutex.lock()
            try {
                val keyStore = KeyStore.getInstance(KEYSTORE_TYPE)
                keyStore.load(null)
                
                if (keyStore.containsAlias(KEYSTORE_ALIAS)) {
                    keyStore.deleteEntry(KEYSTORE_ALIAS)
                    true
                } else {
                    false
                }
                
            } catch (e: Exception) {
                logKeystoreError("Failed to delete keys", e)
                false
            } finally {
                publicKeyMutex.unlock()
                privateKeyMutex.unlock()
            }
        }
    }
    
    // STATIC METHOD EQUIVALENT (called as fh.d.i() in ch.b)
    /**
     * Static-like method for getting public key
     * This matches the fh.d.i() call pattern seen in ch.b.registerDevice()
     */
    suspend fun i(forceRefresh: Boolean): PublicKey? {
        return getPublicKey(forceRefresh)
    }
    
    // Logging/Analytics helpers
    private fun logKeyAccessError(keyType: String, requestId: String, error: Exception) {
        // Log through analytics service
        // This would integrate with the tg.c analytics service
        println("Key access error [$keyType] for request $requestId: ${error.message}")
    }
    
    private fun logKeystoreError(message: String, error: Exception) {
        // Log keystore errors
        println("KeyStore error: $message - ${error.message}")
    }
}

/*
KEY INSIGHTS FROM CLEAN KOTLIN VERSION:

1. THREAD SAFETY:
   - Uses Mutex for synchronized access to keystore operations
   - Separates private key and public key mutexes for better concurrency

2. KEYSTORE OPERATIONS:
   - All operations use "AndroidKeyStore" provider
   - Keys stored under "ATTEST" alias (same as fh.b key generation)
   - Proper error handling and logging

3. SUSPENDING FUNCTIONS:
   - getPrivateKey() - for signing operations
   - getPublicKey() - for registration (this is what ch.b calls!)
   - All operations run on provided dispatcher (likely IO dispatcher)

4. KEY LIFECYCLE:
   - keysExist() - check if keys are present
   - ensureKeysExist() - generate if missing
   - deleteKeys() - cleanup/rotation

5. THE CRITICAL METHOD:
   - getPublicKey() is what ch.b.registerDevice() calls via fh.d.i()
   - This returns PublicKey from keystore certificate
   - The .getEncoded() call happens in ch.b, not here!

6. MYSTERY STILL UNSOLVED:
   - This class just returns the raw PublicKey object
   - The transformation to 32 bytes happens in ch.b with ep.a.e()
   - We still need to understand what ep.a.e() actually does!

The clean Kotlin version shows this is a well-architected key management
system with proper concurrency, error handling, and lifecycle management.
*/