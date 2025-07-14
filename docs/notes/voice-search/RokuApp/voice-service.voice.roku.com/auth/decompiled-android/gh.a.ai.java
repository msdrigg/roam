//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
//

package gh;

import cy.p;
import dy.w0;
import dy.x;
import fh.d;
import fh.e;
import java.security.PrivateKey;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.Locale;
import java.util.Set;
import kotlin.collections.u;
import kotlin.coroutines.jvm.internal.f;
import kotlin.coroutines.jvm.internal.l;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlinx.coroutines.BuildersKt;
import kotlinx.coroutines.CoroutineScope;
import okhttp3.Request;
import okhttp3.RequestBody;
import px.m;
import px.o;
import px.v;
import tg.c;
import tx.g;
import ux.b;

public final class a {
    public static final gh.a.a h = new gh.a.a((DefaultConstructorMarker)null);
    private final ch.a attestRepository;
    private final jh.a attestationStore;
    private final d attestKeyPairProvider;
    private final cy.a<String> clientIdProvider;
    private final e attestationBaseHeaderHelper;
    private final sl.a apiTierProvider;
    private final c analyticsService;

    public a(ch.a attestRepo, jh.a attestStore, d keyPairProvider, cy.a<String> clientId, e headerHelper, sl.a tierProvider, c analytics) {
        x.i(attestRepo, "attestRepository");
        x.i(attestStore, "attestationStore");
        x.i(keyPairProvider, "attestKeyPairProvider");
        x.i(clientId, "clientId");
        x.i(headerHelper, "attestationBaseHeaderHelper");
        x.i(tierProvider, "apiTierProvider");
        x.i(analytics, "analyticsService");
        super();
        this.attestRepository = attestRepo;
        this.attestationStore = attestStore;
        this.attestKeyPairProvider = keyPairProvider;
        this.clientIdProvider = clientId;
        this.attestationBaseHeaderHelper = headerHelper;
        this.apiTierProvider = tierProvider;
        this.analyticsService = analytics;
    }

    private final void appendAssertionChallengeHeader(String challenge, StringBuilder signedHeaders, StringBuilder canonicalHeaders) {
        signedHeaders.append("assertion-challenge");
        canonicalHeaders.append("assertion-challenge");
        canonicalHeaders.append(":");
        canonicalHeaders.append(challenge);
        canonicalHeaders.append("\n");
    }

    private final void appendApiWebEnvHeader(StringBuilder signedHeaders, StringBuilder canonicalHeaders) {
        signedHeaders.append("apiweb-env");
        canonicalHeaders.append("apiweb-env");
        canonicalHeaders.append(":");
        canonicalHeaders.append(this.apiTierProvider.b().getTierName());
        canonicalHeaders.append("\n");
    }

    private final void appendTimestampHeader(String timestamp, StringBuilder signedHeaders, StringBuilder canonicalHeaders) {
        signedHeaders.append("assertion-request-ts");
        canonicalHeaders.append("assertion-request-ts");
        canonicalHeaders.append(":");
        canonicalHeaders.append(timestamp);
        canonicalHeaders.append("\n");
    }

    private final kh.a callAssertionApi(kh.a.d requestData, String requestId) {
        @f(
            c = "com.roku.mobile.attestation.implementation.Assertion$callAssertionApi$1",
            f = "Assertion.kt",
            l = {84},
            m = "invokeSuspend"
        )
        final class NamelessClass_1 extends l implements p<CoroutineScope, tx.d<? super kh.a>, Object> {
            int label;
            final gh.a assertion;
            final kh.a.d apiRequestData;
            final String apiRequestId;

            NamelessClass_1(gh.a assertionInstance, kh.a.d requestData, String requestId, tx.d<? super NamelessClass_1> continuation) {
                super(2, continuation);
                this.assertion = assertionInstance;
                this.apiRequestData = requestData;
                this.apiRequestId = requestId;
            }

            public final tx.d<v> create(Object coroutineScope, tx.d<?> continuation) {
                return new NamelessClass_1(this.assertion, this.apiRequestData, this.apiRequestId, continuation);
            }

            public final Object invoke(CoroutineScope scope, tx.d<? super kh.a> continuation) {
                return ((NamelessClass_1)this.create(scope, continuation)).invokeSuspend(v.a);
            }

            public final Object invokeSuspend(Object result) {
                Object coroutineMarker = ux.b.d();
                int currentLabel = this.label;
                if (currentLabel != 0) {
                    if (currentLabel != 1) {
                        throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                    }

                    o.b(result);
                } else {
                    o.b(result);
                    ch.a repository = this.assertion.attestRepository;
                    kh.a.d requestData = this.apiRequestData;
                    String clientId = (String)this.assertion.clientIdProvider.invoke();
                    String requestId = this.apiRequestId;
                    this.label = 1;
                    Object apiResult = repository.Q(requestData, clientId, requestId, this);
                    result = apiResult;
                    if (apiResult == coroutineMarker) {
                        return coroutineMarker;
                    }
                }

                return result;
            }
        }

        return (kh.a)BuildersKt.f((g)null, new NamelessClass_1(this, requestData, requestId, (tx.d)null), 1, (Object)null);
    }

    private final Object createSignedRequest(Request originalRequest, String challenge, String requestId, tx.d<? super Request> continuation) {
        int label;

        @f(
            c = "com.roku.mobile.attestation.implementation.Assertion",
            f = "Assertion.kt",
            l = {118, 126},
            m = "createSignedRequest"
        )
        final class NamelessClass_2 extends kotlin.coroutines.jvm.internal.d {
            Object resultObject;
            Object requestObject;
            Object headerBuilder;
            Object signatureObject;
            Object timestampObject;
            final gh.a assertion;
            int labelState;

            NamelessClass_2(gh.a assertionInstance, tx.d<? super NamelessClass_2> continuation) {
                super(continuation);
                this.assertion = assertionInstance;
            }

            public final Object invokeSuspend(Object result) {
                this.timestampObject = result;
                this.labelState |= Integer.MIN_VALUE;
                return this.assertion.createSignedRequest((Request)null, (String)null, (String)null, this);
            }
        }

        NamelessClass_2 continuationState;
        label48: {
            if (continuation instanceof NamelessClass_2) {
                NamelessClass_2 existingState = (NamelessClass_2)continuation;
                label = existingState.labelState;
                if ((label & Integer.MIN_VALUE) != 0) {
                    existingState.labelState = label + Integer.MIN_VALUE;
                    continuationState = existingState;
                    break label48;
                }
            }

            continuationState = new NamelessClass_2(this, continuation);
        }

        StringBuilder signedHeadersList;
        gh.a assertionInstance;
        Request builtRequest;
        Object coroutineResult;
        String timestamp;
        label51: {
            coroutineResult = continuationState.timestampObject;
            Object coroutineMarker = ux.b.d();
            label = continuationState.labelState;
            Object signatureResult;
            Request requestWithHeaders;
            if (label != 0) {
                if (label != 1) {
                    if (label != 2) {
                        throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                    }

                    requestId = (String)continuationState.signatureObject;
                    signedHeadersList = (StringBuilder)continuationState.headerBuilder;
                    Request originalReq = (Request)continuationState.requestObject;
                    gh.a assertion = (gh.a)continuationState.resultObject;
                    o.b(coroutineResult);
                    builtRequest = originalReq;
                    assertionInstance = assertion;
                    break label51;
                }

                signedHeadersList = (StringBuilder)continuationState.signatureObject;
                requestWithHeaders = (Request)continuationState.headerBuilder;
                String timestampStr = (String)continuationState.requestObject;
                assertionInstance = (gh.a)continuationState.resultObject;
                o.b(coroutineResult);
                signatureResult = coroutineResult;
                timestamp = timestampStr;
            } else {
                o.b(coroutineResult);
                timestamp = String.valueOf(cj.e.a.e());
                Request.Builder requestBuilder = originalRequest.newBuilder();
                this.attestationBaseHeaderHelper.a(requestBuilder);
                requestBuilder.header("assertion-challenge", challenge);
                requestBuilder.header("apiweb-env", this.apiTierProvider.b().getTierName());
                requestBuilder.header("x-roku-reserved-client-id", (String)this.clientIdProvider.invoke());
                requestBuilder.header("assertion-request-ts", timestamp);
                requestBuilder.header("host", originalRequest.url().host());
                requestBuilder.header("salt", "roku");
                Request requestWithAllHeaders = requestBuilder.build();
                m headersPair = this.buildCanonicalHeaders(challenge, requestWithAllHeaders, timestamp);
                StringBuilder signedHeaders = (StringBuilder)headersPair.a();
                StringBuilder canonicalHeaders = (StringBuilder)headersPair.b();
                continuationState.resultObject = this;
                continuationState.requestObject = requestId;
                continuationState.headerBuilder = requestWithAllHeaders;
                continuationState.signatureObject = signedHeaders;
                continuationState.labelState = 1;
                Object signatureValue = this.prepareSignedPayload(challenge, originalRequest, timestamp, signedHeaders, canonicalHeaders, requestId, continuationState);
                if (signatureValue == coroutineMarker) {
                    return coroutineMarker;
                }

                timestamp = requestId;
                assertionInstance = this;
                signedHeadersList = signedHeaders;
                requestWithHeaders = requestWithAllHeaders;
                signatureResult = signatureValue;
            }

            String signature = (String)signatureResult;
            d keyProvider = assertionInstance.attestKeyPairProvider;
            continuationState.resultObject = assertionInstance;
            continuationState.requestObject = requestWithHeaders;
            continuationState.headerBuilder = signedHeadersList;
            continuationState.signatureObject = signature;
            continuationState.labelState = 2;
            coroutineResult = keyProvider.g(timestamp, continuationState);
            if (coroutineResult == coroutineMarker) {
                return coroutineMarker;
            }

            builtRequest = requestWithHeaders;
            requestId = signature;
        }

        PrivateKey privateKey = (PrivateKey)coroutineResult;
        if (privateKey != null) {
            byte[] saltBytes = "roku".getBytes(r00.d.b);
            x.h(saltBytes, "this as java.lang.String).getBytes(charset)");
            timestamp = ep.a.e(ep.a.d(saltBytes, (String)null, privateKey, 1, (Object)null));
        } else {
            timestamp = null;
        }

        if (requestId != null && timestamp != null) {
            Request.Builder finalRequestBuilder = builtRequest.newBuilder();
            StringBuilder signatureHeader = new StringBuilder();
            signatureHeader.append("hash_alg");
            signatureHeader.append("=");
            signatureHeader.append("HMAC_SHA256");
            signatureHeader.append(", ");
            signatureHeader.append("client_id");
            signatureHeader.append("=");
            signatureHeader.append((String)assertionInstance.clientIdProvider.invoke());
            signatureHeader.append(", ");
            signatureHeader.append("signed_headers");
            signatureHeader.append("=");
            signatureHeader.append(signedHeadersList);
            signatureHeader.append(", ");
            signatureHeader.append("signature");
            signatureHeader.append("=");
            signatureHeader.append(requestId);
            signatureHeader.append(", ");
            signatureHeader.append("salt");
            signatureHeader.append("=");
            signatureHeader.append(timestamp);
            String signatureHeaderValue = signatureHeader.toString();
            x.h(signatureHeaderValue, "StringBuilder().append(A…              .toString()");
            return finalRequestBuilder.header("assertion-signature", signatureHeaderValue).build();
        } else {
            return null;
        }
    }

    private final String hashRequestBody(Request request) {
        RequestBody requestBody = request.body();
        Object nullRef = null;
        byte[] bodyHash;
        String hashedBody;
        if (requestBody != null) {
            okio.c buffer = new okio.c();
            requestBody.writeTo(buffer);
            bodyHash = ep.a.a(buffer.H0());
            if (bodyHash != null) {
                hashedBody = ep.a.f(bodyHash);
            } else {
                hashedBody = null;
            }

            if (hashedBody != null) {
                return hashedBody;
            }
        }

        bodyHash = "".getBytes(r00.d.b);
        x.h(bodyHash, "this as java.lang.String).getBytes(charset)");
        byte[] emptyBodyHash = ep.a.a(bodyHash);
        hashedBody = (String)nullRef;
        if (emptyBodyHash != null) {
            hashedBody = ep.a.f(emptyBodyHash);
        }

        return hashedBody;
    }

    private final void appendHostHeader(String hostValue, StringBuilder signedHeaders, StringBuilder canonicalHeaders) {
        signedHeaders.append("host");
        canonicalHeaders.append("host");
        canonicalHeaders.append(":");
        canonicalHeaders.append(hostValue);
        canonicalHeaders.append("\n");
    }

    private final m<StringBuilder, StringBuilder> buildCanonicalHeaders(String challenge, Request request, String timestamp) {
        StringBuilder signedHeadersList = new StringBuilder();
        StringBuilder canonicalHeadersList = new StringBuilder();
        Set headerNames = request.headers().names();
        ArrayList lowercaseHeaders = new ArrayList();
        Iterator headerIterator = headerNames.iterator();

        while(headerIterator.hasNext()) {
            Object headerName = headerIterator.next();
            if (Character.isLowerCase(r00.m.c1((String)headerName))) {
                lowercaseHeaders.add(headerName);
            }
        }

        Iterator sortedHeaderIterator = u.X0(u.j1(lowercaseHeaders), r00.m.v(w0.a)).iterator();

        while(true) {
            while(sortedHeaderIterator.hasNext()) {
                String currentHeader = (String)sortedHeaderIterator.next();
                Locale usLocale = Locale.US;
                x.h(usLocale, "US");
                String lowerCaseHeader = currentHeader.toLowerCase(usLocale);
                x.h(lowerCaseHeader, "this as java.lang.String).toLowerCase(locale)");
                boolean needsSeparator;
                if (signedHeadersList.length() > 0) {
                    needsSeparator = true;
                } else {
                    needsSeparator = false;
                }

                if (needsSeparator) {
                    signedHeadersList.append(";");
                }

                switch (lowerCaseHeader) {
                    case "assertion-request-ts":
                        this.appendTimestampHeader(timestamp, signedHeadersList, canonicalHeadersList);
                        continue;
                        break;
                    case "host":
                        this.appendHostHeader(request.url().host(), signedHeadersList, canonicalHeadersList);
                        continue;
                        break;
                    case "assertion-challenge":
                        this.appendAssertionChallengeHeader(challenge, signedHeadersList, canonicalHeadersList);
                        continue;
                        break;
                    case "apiweb-env":
                        this.appendApiWebEnvHeader(signedHeadersList, canonicalHeadersList);
                        continue;
                }

                signedHeadersList.append(lowerCaseHeader);
                currentHeader = (String)u.s0(request.headers().values(currentHeader));
                if (currentHeader != null) {
                    canonicalHeadersList.append(lowerCaseHeader);
                    canonicalHeadersList.append(":");
                    canonicalHeadersList.append(currentHeader);
                    canonicalHeadersList.append("\n");
                }
            }

            return new m(signedHeadersList, canonicalHeadersList);
        }
    }

    private final byte[] createStringToSign(String hashedCanonicalRequest, String challenge, String timestamp) {
        StringBuilder stringToSign = new StringBuilder();
        stringToSign.append("HMAC_SHA256");
        stringToSign.append("\n");
        stringToSign.append(timestamp);
        stringToSign.append("\n");
        stringToSign.append((String)this.clientIdProvider.invoke());
        stringToSign.append("\n");
        stringToSign.append(challenge);
        stringToSign.append("\n");
        stringToSign.append(hashedCanonicalRequest);
        hashedCanonicalRequest = stringToSign.toString();
        x.h(hashedCanonicalRequest, "StringBuilder().append(A… .append(this).toString()");
        byte[] stringToSignBytes = hashedCanonicalRequest.getBytes(r00.d.b);
        x.h(stringToSignBytes, "this as java.lang.String).getBytes(charset)");
        return stringToSignBytes;
    }

    private final Object prepareSignedPayload(String challenge, Request originalRequest, String timestamp, StringBuilder signedHeaders, StringBuilder canonicalHeaders, String requestId, tx.d<? super String> continuation) {
        int label;

        @f(
            c = "com.roku.mobile.attestation.implementation.Assertion",
            f = "Assertion.kt",
            l = {264},
            m = "prepareSignedPayload"
        )
        final class NamelessClass_4 extends kotlin.coroutines.jvm.internal.d {
            Object resultObject;
            Object stateObject;
            final gh.a assertion;
            int labelState;

            NamelessClass_4(gh.a assertionInstance, tx.d<? super NamelessClass_4> continuation) {
                super(continuation);
                this.assertion = assertionInstance;
            }

            public final Object invokeSuspend(Object result) {
                this.stateObject = result;
                this.labelState |= Integer.MIN_VALUE;
                return this.assertion.prepareSignedPayload((String)null, (Request)null, (String)null, (StringBuilder)null, (StringBuilder)null, (String)null, this);
            }
        }

        NamelessClass_4 continuationState;
        label54: {
            if (continuation instanceof NamelessClass_4) {
                NamelessClass_4 existingState = (NamelessClass_4)continuation;
                label = existingState.labelState;
                if ((label & Integer.MIN_VALUE) != 0) {
                    existingState.labelState = label + Integer.MIN_VALUE;
                    continuationState = existingState;
                    break label54;
                }
            }

            continuationState = new NamelessClass_4(this, continuation);
        }

        Object coroutineResult = continuationState.stateObject;
        Object coroutineMarker = ux.b.d();
        label = continuationState.labelState;
        Object nullRef = null;
        byte[] stringToSignBytes;
        Object privateKeyResult;
        String hashedCanonicalRequest;
        if (label != 0) {
            if (label != 1) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }

            stringToSignBytes = (byte[])continuationState.resultObject;
            o.b(coroutineResult);
            privateKeyResult = coroutineResult;
        } else {
            o.b(coroutineResult);
            String bodyHash = this.hashRequestBody(originalRequest);
            String hashedBody = bodyHash;
            if (bodyHash == null) {
                hashedBody = "";
            }

            bodyHash = ip.a.a(originalRequest.url());
            String queryString = ip.a.b(originalRequest.url());
            String httpMethod = originalRequest.method();
            StringBuilder canonicalRequest = new StringBuilder();
            canonicalRequest.append(httpMethod);
            canonicalRequest.append("\n");
            canonicalRequest.append(bodyHash);
            canonicalRequest.append("\n");
            canonicalRequest.append(queryString);
            canonicalRequest.append("\n");
            canonicalRequest.append(canonicalHeaders);
            canonicalRequest.append("\n");
            canonicalRequest.append(signedHeaders);
            canonicalRequest.append("\n");
            canonicalRequest.append(hashedBody);
            byte[] canonicalRequestBytes = canonicalRequest.toString().getBytes(r00.d.b);
            x.h(canonicalRequestBytes, "this as java.lang.String).getBytes(charset)");
            canonicalRequestBytes = ep.a.a(canonicalRequestBytes);
            if (canonicalRequestBytes != null) {
                hashedCanonicalRequest = ep.a.f(canonicalRequestBytes);
            } else {
                hashedCanonicalRequest = null;
            }

            label44: {
                if (hashedCanonicalRequest != null) {
                    stringToSignBytes = this.createStringToSign(hashedCanonicalRequest, challenge, timestamp);
                    if (stringToSignBytes != null) {
                        stringToSignBytes = ep.a.a(stringToSignBytes);
                        break label44;
                    }
                }

                stringToSignBytes = null;
            }

            if (stringToSignBytes != null) {
                hashedCanonicalRequest = ep.a.f(stringToSignBytes);
            } else {
                hashedCanonicalRequest = null;
            }

            @f(
                c = "com.roku.mobile.attestation.implementation.Assertion$prepareSignedPayload$2",
                f = "Assertion.kt",
                l = {262},
                m = "invokeSuspend"
            )
            final class NamelessClass_5 extends l implements p<CoroutineScope, tx.d<? super v>, Object> {
                int label;
                final gh.a assertion;
                final String requestIdValue;
                final String signatureValue;

                NamelessClass_5(gh.a assertionInstance, String reqId, String signature, tx.d<? super NamelessClass_5> continuation) {
                    super(2, continuation);
                    this.assertion = assertionInstance;
                    this.requestIdValue = reqId;
                    this.signatureValue = signature;
                }

                public final tx.d<v> create(Object coroutineScope, tx.d<?> continuation) {
                    return new NamelessClass_5(this.assertion, this.requestIdValue, this.signatureValue, continuation);
                }

                public final Object invoke(CoroutineScope scope, tx.d<? super v> continuation) {
                    return ((NamelessClass_5)this.create(scope, continuation)).invokeSuspend(v.a);
                }

                public final Object invokeSuspend(Object result) {
                    Object coroutineMarker = ux.b.d();
                    int currentLabel = this.label;
                    if (currentLabel != 0) {
                        if (currentLabel != 1) {
                            throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                        }

                        o.b(result);
                    } else {
                        o.b(result);
                        gh.a assertionInstance = this.assertion;
                        String requestId = this.requestIdValue;
                        String signature = this.signatureValue;
                        this.label = 1;
                        if (assertionInstance.storeSignature(requestId, signature, this) == coroutineMarker) {
                            return coroutineMarker;
                        }
                    }

                    return v.a;
                }
            }

            BuildersKt.f((g)null, new NamelessClass_5(this, requestId, hashedCanonicalRequest, (tx.d)null), 1, (Object)null);
            d keyProvider = this.attestKeyPairProvider;
            continuationState.resultObject = stringToSignBytes;
            continuationState.labelState = 1;
            Object keyResult = keyProvider.g(requestId, continuationState);
            privateKeyResult = keyResult;
            if (keyResult == coroutineMarker) {
                return coroutineMarker;
            }
        }

        PrivateKey privateKey = (PrivateKey)privateKeyResult;
        hashedCanonicalRequest = (String)nullRef;
        if (privateKey != null) {
            hashedCanonicalRequest = (String)nullRef;
            if (stringToSignBytes != null) {
                stringToSignBytes = ep.a.d(stringToSignBytes, (String)null, privateKey, 1, (Object)null);
                hashedCanonicalRequest = (String)nullRef;
                if (stringToSignBytes != null) {
                    hashedCanonicalRequest = ep.a.e(stringToSignBytes);
                }
            }
        }

        return hashedCanonicalRequest;
    }

    private final Object storeSignature(String requestId, String signature, tx.d<? super v> continuation) {
        if (signature != null) {
            Object storeResult = this.attestationStore.b(requestId, signature, continuation);
            return storeResult == ux.b.d() ? storeResult : v.a;
        } else {
            return v.a;
        }
    }

    public final Object prepareAssertionRequest(Request originalRequest, kh.a.d requestData, String requestId, tx.d<? super Request> continuation) {
        int label;

        @f(
            c = "com.roku.mobile.attestation.implementation.Assertion",
            f = "Assertion.kt",
            l = {61},
            m = "prepareAssertionRequest"
        )
        final class NamelessClass_3 extends kotlin.coroutines.jvm.internal.d {
            Object resultObject;
            Object requestIdObject;
            Object stateObject;
            final gh.a assertion;
            int labelState;

            NamelessClass_3(gh.a assertionInstance, tx.d<? super NamelessClass_3> continuation) {
                super(continuation);
                this.assertion = assertionInstance;
            }

            public final Object invokeSuspend(Object result) {
                this.stateObject = result;
                this.labelState |= Integer.MIN_VALUE;
                return this.assertion.prepareAssertionRequest((Request)null, (kh.a.d)null, (String)null, this);
            }
        }

        NamelessClass_3 continuationState;
        label71: {
            if (continuation instanceof NamelessClass_3) {
                NamelessClass_3 existingState = (NamelessClass_3)continuation;
                label = existingState.labelState;
                if ((label & Integer.MIN_VALUE) != 0) {
                    existingState.labelState = label + Integer.MIN_VALUE;
                    continuationState = existingState;
                    break label71;
                }
            }

            continuationState = new NamelessClass_3(this, continuation);
        }

        String currentRequestId;
        Exception caughtException;
        String finalRequestId;
        gh.a assertionInstance;
        label64: {
            gh.a currentAssertion;
            Exception exception;
            label74: {
                Object coroutineResult = continuationState.stateObject;
                Object coroutineMarker = ux.b.d();
                label = continuationState.labelState;
                boolean exceptionOccurred;
                gh.a workingAssertion;
                if (label != 0) {
                    if (label != 1) {
                        throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                    }

                    requestId = (String)continuationState.requestIdObject;
                    workingAssertion = (gh.a)continuationState.resultObject;
                    currentAssertion = workingAssertion;
                    currentRequestId = requestId;

                    try {
                        o.b(coroutineResult);
                    } catch (Exception ex) {
                        exception = ex;
                        exceptionOccurred = false;
                        break label74;
                    }
                } else {
                    o.b(coroutineResult);
                    kh.a apiResponse = this.callAssertionApi(requestData, requestId);
                    if (!(apiResponse instanceof kh.a.g)) {
                        return null;
                    }

                    bh.e.l(this.analyticsService, requestId);

                    try {
                        finalRequestId = ((kh.a.g)apiResponse).a();
                        continuationState.resultObject = this;
                        continuationState.requestIdObject = requestId;
                        continuationState.labelState = 1;
                        coroutineResult = this.createSignedRequest(originalRequest, finalRequestId, requestId, continuationState);
                    } catch (Exception ex) {
                        caughtException = ex;
                        currentRequestId = requestId;
                        assertionInstance = this;
                        break label64;
                    }

                    if (coroutineResult == coroutineMarker) {
                        return coroutineMarker;
                    }

                    workingAssertion = this;
                }

                currentAssertion = workingAssertion;
                currentRequestId = requestId;

                Request signedRequest;
                try {
                    signedRequest = (Request)coroutineResult;
                } catch (Exception ex) {
                    exception = ex;
                    exceptionOccurred = false;
                    break label74;
                }

                if (signedRequest != null) {
                    currentAssertion = workingAssertion;
                    currentRequestId = requestId;

                    try {
                        bh.e.m(workingAssertion.analyticsService, requestId);
                    } catch (Exception ex) {
                        exception = ex;
                        exceptionOccurred = false;
                        break label74;
                    }
                }

                return signedRequest;
            }

            Exception thrownException = exception;
            assertionInstance = currentAssertion;
            caughtException = thrownException;
        }

        l10.a.b logger = l10.a.a;
        StringBuilder logTag = new StringBuilder();
        logTag.append("Assertion_");
        logTag.append(currentRequestId);
        logger.w(logTag.toString()).e(caughtException);
        c analytics = assertionInstance.analyticsService;
        requestId = caughtException.getClass().getName();
        finalRequestId = caughtException.getMessage();
        StringBuilder errorMessage = new StringBuilder();
        errorMessage.append(requestId);
        errorMessage.append(" ");
        errorMessage.append(finalRequestId);
        bh.e.k(analytics, currentRequestId, errorMessage.toString());
        return null;
    }

    public static final class a {
        private a() {
        }
    }
}