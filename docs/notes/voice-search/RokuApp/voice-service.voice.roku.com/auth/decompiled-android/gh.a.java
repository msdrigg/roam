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
    private final ch.a a;
    private final jh.a b;
    private final d c;
    private final cy.a<String> d;
    private final e e;
    private final sl.a f;
    private final c g;

    public a(ch.a var1, jh.a var2, d var3, cy.a<String> var4, e var5, sl.a var6, c var7) {
        x.i(var1, "attestRepository");
        x.i(var2, "attestationStore");
        x.i(var3, "attestKeyPairProvider");
        x.i(var4, "clientId");
        x.i(var5, "attestationBaseHeaderHelper");
        x.i(var6, "apiTierProvider");
        x.i(var7, "analyticsService");
        super();
        this.a = var1;
        this.b = var2;
        this.c = var3;
        this.d = var4;
        this.e = var5;
        this.f = var6;
        this.g = var7;
    }

    private final void f(String var1, StringBuilder var2, StringBuilder var3) {
        var2.append("assertion-challenge");
        var3.append("assertion-challenge");
        var3.append(":");
        var3.append(var1);
        var3.append("\n");
    }

    private final void g(StringBuilder var1, StringBuilder var2) {
        var1.append("apiweb-env");
        var2.append("apiweb-env");
        var2.append(":");
        var2.append(this.f.b().getTierName());
        var2.append("\n");
    }

    private final void h(String var1, StringBuilder var2, StringBuilder var3) {
        var2.append("assertion-request-ts");
        var3.append("assertion-request-ts");
        var3.append(":");
        var3.append(var1);
        var3.append("\n");
    }

    private final kh.a i(kh.a.d var1, String var2) {
        @f(
            c = "com.roku.mobile.attestation.implementation.Assertion$callAssertionApi$1",
            f = "Assertion.kt",
            l = {84},
            m = "invokeSuspend"
        )
        final class NamelessClass_1 extends l implements p<CoroutineScope, tx.d<? super kh.a>, Object> {
            int h;
            final gh.a i;
            final kh.a.d j;
            final String k;

            NamelessClass_1(gh.a var1, kh.a.d var2, String var3, tx.d<? super NamelessClass_1> var4) {
                super(2, var4);
                this.i = var1;
                this.j = var2;
                this.k = var3;
            }

            public final tx.d<v> create(Object var1, tx.d<?> var2) {
                return new NamelessClass_1(this.i, this.j, this.k, var2);
            }

            public final Object invoke(CoroutineScope var1, tx.d<? super kh.a> var2) {
                return ((NamelessClass_1)this.create(var1, var2)).invokeSuspend(v.a);
            }

            public final Object invokeSuspend(Object var1) {
                Object var4 = ux.b.d();
                int var2 = this.h;
                if (var2 != 0) {
                    if (var2 != 1) {
                        throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                    }

                    o.b(var1);
                } else {
                    o.b(var1);
                    ch.a var5 = this.i.a;
                    kh.a.d var6 = this.j;
                    String var7 = (String)this.i.d.invoke();
                    String var3 = this.k;
                    this.h = 1;
                    Object var8 = var5.Q(var6, var7, var3, this);
                    var1 = var8;
                    if (var8 == var4) {
                        return var4;
                    }
                }

                return var1;
            }
        }

        return (kh.a)BuildersKt.f((g)null, new NamelessClass_1(this, var1, var2, (tx.d)null), 1, (Object)null);
    }

    private final Object j(Request var1, String var2, String var3, tx.d<? super Request> var4) {
        int var5;

        @f(
            c = "com.roku.mobile.attestation.implementation.Assertion",
            f = "Assertion.kt",
            l = {118, 126},
            m = "createSignedRequest"
        )
        final class NamelessClass_2 extends kotlin.coroutines.jvm.internal.d {
            Object h;
            Object i;
            Object j;
            Object k;
            Object l;
            final gh.a m;
            int n;

            NamelessClass_2(gh.a var1, tx.d<? super NamelessClass_2> var2) {
                super(var2);
                this.m = var1;
            }

            public final Object invokeSuspend(Object var1) {
                this.l = var1;
                this.n |= Integer.MIN_VALUE;
                return this.m.j((Request)null, (String)null, (String)null, this);
            }
        }

        NamelessClass_2 var16;
        label48: {
            if (var4 instanceof NamelessClass_2) {
                NamelessClass_2 var6 = (NamelessClass_2)var4;
                var5 = var6.n;
                if ((var5 & Integer.MIN_VALUE) != 0) {
                    var6.n = var5 + Integer.MIN_VALUE;
                    var16 = var6;
                    break label48;
                }
            }

            var16 = new NamelessClass_2(this, var4);
        }

        StringBuilder var11;
        gh.a var12;
        Request var17;
        Object var18;
        String var20;
        label51: {
            var18 = var16.l;
            Object var10 = ux.b.d();
            var5 = var16.n;
            Object var7;
            Request var15;
            if (var5 != 0) {
                if (var5 != 1) {
                    if (var5 != 2) {
                        throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                    }

                    var3 = (String)var16.k;
                    var11 = (StringBuilder)var16.j;
                    Request var13 = (Request)var16.i;
                    gh.a var21 = (gh.a)var16.h;
                    o.b(var18);
                    var17 = var13;
                    var12 = var21;
                    break label51;
                }

                var11 = (StringBuilder)var16.k;
                var15 = (Request)var16.j;
                String var8 = (String)var16.i;
                var12 = (gh.a)var16.h;
                o.b(var18);
                var7 = var18;
                var20 = var8;
            } else {
                o.b(var18);
                var20 = String.valueOf(cj.e.a.e());
                Request.Builder var22 = var1.newBuilder();
                this.e.a(var22);
                var22.header("assertion-challenge", var2);
                var22.header("apiweb-env", this.f.b().getTierName());
                var22.header("x-roku-reserved-client-id", (String)this.d.invoke());
                var22.header("assertion-request-ts", var20);
                var22.header("host", var1.url().host());
                var22.header("salt", "roku");
                Request var23 = var22.build();
                m var9 = this.n(var2, var23, var20);
                StringBuilder var24 = (StringBuilder)var9.a();
                StringBuilder var28 = (StringBuilder)var9.b();
                var16.h = this;
                var16.i = var3;
                var16.j = var23;
                var16.k = var24;
                var16.n = 1;
                Object var30 = this.p(var2, var1, var20, var24, var28, var3, var16);
                if (var30 == var10) {
                    return var10;
                }

                var20 = var3;
                var12 = this;
                var11 = var24;
                var15 = var23;
                var7 = var30;
            }

            String var27 = (String)var7;
            d var25 = var12.c;
            var16.h = var12;
            var16.i = var15;
            var16.j = var11;
            var16.k = var27;
            var16.n = 2;
            var18 = var25.g(var20, var16);
            if (var18 == var10) {
                return var10;
            }

            var17 = var15;
            var3 = var27;
        }

        PrivateKey var29 = (PrivateKey)var18;
        if (var29 != null) {
            byte[] var26 = "roku".getBytes(r00.d.b);
            x.h(var26, "this as java.lang.String).getBytes(charset)");
            var20 = ep.a.e(ep.a.d(var26, (String)null, var29, 1, (Object)null));
        } else {
            var20 = null;
        }

        if (var3 != null && var20 != null) {
            Request.Builder var19 = var17.newBuilder();
            StringBuilder var31 = new StringBuilder();
            var31.append("hash_alg");
            var31.append("=");
            var31.append("HMAC_SHA256");
            var31.append(", ");
            var31.append("client_id");
            var31.append("=");
            var31.append((String)var12.d.invoke());
            var31.append(", ");
            var31.append("signed_headers");
            var31.append("=");
            var31.append(var11);
            var31.append(", ");
            var31.append("signature");
            var31.append("=");
            var31.append(var3);
            var31.append(", ");
            var31.append("salt");
            var31.append("=");
            var31.append(var20);
            String var14 = var31.toString();
            x.h(var14, "StringBuilder().append(A…              .toString()");
            return var19.header("assertion-signature", var14).build();
        } else {
            return null;
        }
    }

    private final String k(Request var1) {
        RequestBody var3 = var1.body();
        Object var2 = null;
        byte[] var5;
        String var6;
        if (var3 != null) {
            okio.c var4 = new okio.c();
            var3.writeTo(var4);
            var5 = ep.a.a(var4.H0());
            if (var5 != null) {
                var6 = ep.a.f(var5);
            } else {
                var6 = null;
            }

            if (var6 != null) {
                return var6;
            }
        }

        var5 = "".getBytes(r00.d.b);
        x.h(var5, "this as java.lang.String).getBytes(charset)");
        byte[] var7 = ep.a.a(var5);
        var6 = (String)var2;
        if (var7 != null) {
            var6 = ep.a.f(var7);
        }

        return var6;
    }

    private final void l(String var1, StringBuilder var2, StringBuilder var3) {
        var2.append("host");
        var3.append("host");
        var3.append(":");
        var3.append(var1);
        var3.append("\n");
    }

    private final m<StringBuilder, StringBuilder> n(String var1, Request var2, String var3) {
        StringBuilder var5 = new StringBuilder();
        StringBuilder var6 = new StringBuilder();
        Set var8 = var2.headers().names();
        ArrayList var7 = new ArrayList();
        Iterator var9 = var8.iterator();

        while(var9.hasNext()) {
            Object var11 = var9.next();
            if (Character.isLowerCase(r00.m.c1((String)var11))) {
                var7.add(var11);
            }
        }

        Iterator var10 = u.X0(u.j1(var7), r00.m.v(w0.a)).iterator();

        while(true) {
            while(var10.hasNext()) {
                String var14 = (String)var10.next();
                Locale var12 = Locale.US;
                x.h(var12, "US");
                String var13 = var14.toLowerCase(var12);
                x.h(var13, "this as java.lang.String).toLowerCase(locale)");
                boolean var4;
                if (var5.length() > 0) {
                    var4 = true;
                } else {
                    var4 = false;
                }

                if (var4) {
                    var5.append(";");
                }

                switch (var13) {
                    case "assertion-request-ts":
                        this.h(var3, var5, var6);
                        continue;
                        break;
                    case "host":
                        this.l(var2.url().host(), var5, var6);
                        continue;
                        break;
                    case "assertion-challenge":
                        this.f(var1, var5, var6);
                        continue;
                        break;
                    case "apiweb-env":
                        this.g(var5, var6);
                        continue;
                }

                var5.append(var13);
                var14 = (String)u.s0(var2.headers().values(var14));
                if (var14 != null) {
                    var6.append(var13);
                    var6.append(":");
                    var6.append(var14);
                    var6.append("\n");
                }
            }

            return new m(var5, var6);
        }
    }

    private final byte[] o(String var1, String var2, String var3) {
        StringBuilder var4 = new StringBuilder();
        var4.append("HMAC_SHA256");
        var4.append("\n");
        var4.append(var3);
        var4.append("\n");
        var4.append((String)this.d.invoke());
        var4.append("\n");
        var4.append(var2);
        var4.append("\n");
        var4.append(var1);
        var1 = var4.toString();
        x.h(var1, "StringBuilder().append(A… .append(this).toString()");
        byte[] var5 = var1.getBytes(r00.d.b);
        x.h(var5, "this as java.lang.String).getBytes(charset)");
        return var5;
    }

    private final Object p(String var1, Request var2, String var3, StringBuilder var4, StringBuilder var5, String var6, tx.d<? super String> var7) {
        int var8;

        @f(
            c = "com.roku.mobile.attestation.implementation.Assertion",
            f = "Assertion.kt",
            l = {264},
            m = "prepareSignedPayload"
        )
        final class NamelessClass_4 extends kotlin.coroutines.jvm.internal.d {
            Object h;
            Object i;
            final gh.a j;
            int k;

            NamelessClass_4(gh.a var1, tx.d<? super NamelessClass_4> var2) {
                super(var2);
                this.j = var1;
            }

            public final Object invokeSuspend(Object var1) {
                this.i = var1;
                this.k |= Integer.MIN_VALUE;
                return this.j.p((String)null, (Request)null, (String)null, (StringBuilder)null, (StringBuilder)null, (String)null, this);
            }
        }

        NamelessClass_4 var23;
        label54: {
            if (var7 instanceof NamelessClass_4) {
                NamelessClass_4 var9 = (NamelessClass_4)var7;
                var8 = var9.k;
                if ((var8 & Integer.MIN_VALUE) != 0) {
                    var9.k = var8 + Integer.MIN_VALUE;
                    var23 = var9;
                    break label54;
                }
            }

            var23 = new NamelessClass_4(this, var7);
        }

        Object var24 = var23.i;
        Object var12 = ux.b.d();
        var8 = var23.k;
        Object var10 = null;
        byte[] var15;
        Object var16;
        String var21;
        if (var8 != 0) {
            if (var8 != 1) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }

            var15 = (byte[])var23.h;
            o.b(var24);
            var16 = var24;
        } else {
            o.b(var24);
            String var11 = this.k(var2);
            String var25 = var11;
            if (var11 == null) {
                var25 = "";
            }

            var11 = ip.a.a(var2.url());
            String var13 = ip.a.b(var2.url());
            String var14 = var2.method();
            StringBuilder var17 = new StringBuilder();
            var17.append(var14);
            var17.append("\n");
            var17.append(var11);
            var17.append("\n");
            var17.append(var13);
            var17.append("\n");
            var17.append(var5);
            var17.append("\n");
            var17.append(var4);
            var17.append("\n");
            var17.append(var25);
            byte[] var18 = var17.toString().getBytes(r00.d.b);
            x.h(var18, "this as java.lang.String).getBytes(charset)");
            var18 = ep.a.a(var18);
            if (var18 != null) {
                var21 = ep.a.f(var18);
            } else {
                var21 = null;
            }

            label44: {
                if (var21 != null) {
                    var15 = this.o(var21, var1, var3);
                    if (var15 != null) {
                        var15 = ep.a.a(var15);
                        break label44;
                    }
                }

                var15 = null;
            }

            if (var15 != null) {
                var21 = ep.a.f(var15);
            } else {
                var21 = null;
            }

            @f(
                c = "com.roku.mobile.attestation.implementation.Assertion$prepareSignedPayload$2",
                f = "Assertion.kt",
                l = {262},
                m = "invokeSuspend"
            )
            final class NamelessClass_5 extends l implements p<CoroutineScope, tx.d<? super v>, Object> {
                int h;
                final gh.a i;
                final String j;
                final String k;

                NamelessClass_5(gh.a var1, String var2, String var3, tx.d<? super NamelessClass_5> var4) {
                    super(2, var4);
                    this.i = var1;
                    this.j = var2;
                    this.k = var3;
                }

                public final tx.d<v> create(Object var1, tx.d<?> var2) {
                    return new NamelessClass_5(this.i, this.j, this.k, var2);
                }

                public final Object invoke(CoroutineScope var1, tx.d<? super v> var2) {
                    return ((NamelessClass_5)this.create(var1, var2)).invokeSuspend(v.a);
                }

                public final Object invokeSuspend(Object var1) {
                    Object var3 = ux.b.d();
                    int var2 = this.h;
                    if (var2 != 0) {
                        if (var2 != 1) {
                            throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                        }

                        o.b(var1);
                    } else {
                        o.b(var1);
                        gh.a var4 = this.i;
                        String var5 = this.j;
                        String var6 = this.k;
                        this.h = 1;
                        if (var4.q(var5, var6, this) == var3) {
                            return var3;
                        }
                    }

                    return v.a;
                }
            }

            BuildersKt.f((g)null, new NamelessClass_5(this, var6, var21, (tx.d)null), 1, (Object)null);
            d var22 = this.c;
            var23.h = var15;
            var23.k = 1;
            Object var19 = var22.g(var6, var23);
            var16 = var19;
            if (var19 == var12) {
                return var12;
            }
        }

        PrivateKey var20 = (PrivateKey)var16;
        var21 = (String)var10;
        if (var20 != null) {
            var21 = (String)var10;
            if (var15 != null) {
                var15 = ep.a.d(var15, (String)null, var20, 1, (Object)null);
                var21 = (String)var10;
                if (var15 != null) {
                    var21 = ep.a.e(var15);
                }
            }
        }

        return var21;
    }

    private final Object q(String var1, String var2, tx.d<? super v> var3) {
        if (var2 != null) {
            Object var4 = this.b.b(var1, var2, var3);
            return var4 == ux.b.d() ? var4 : v.a;
        } else {
            return v.a;
        }
    }

    public final Object m(Request var1, kh.a.d var2, String var3, tx.d<? super Request> var4) {
        int var5;

        @f(
            c = "com.roku.mobile.attestation.implementation.Assertion",
            f = "Assertion.kt",
            l = {61},
            m = "prepareAssertionRequest"
        )
        final class NamelessClass_3 extends kotlin.coroutines.jvm.internal.d {
            Object h;
            Object i;
            Object j;
            final gh.a k;
            int l;

            NamelessClass_3(gh.a var1, tx.d<? super NamelessClass_3> var2) {
                super(var2);
                this.k = var1;
            }

            public final Object invokeSuspend(Object var1) {
                this.j = var1;
                this.l |= Integer.MIN_VALUE;
                return this.k.m((Request)null, (kh.a.d)null, (String)null, this);
            }
        }

        NamelessClass_3 var18;
        label71: {
            if (var4 instanceof NamelessClass_3) {
                NamelessClass_3 var6 = (NamelessClass_3)var4;
                var5 = var6.l;
                if ((var5 & Integer.MIN_VALUE) != 0) {
                    var6.l = var5 + Integer.MIN_VALUE;
                    var18 = var6;
                    break label71;
                }
            }

            var18 = new NamelessClass_3(this, var4);
        }

        String var12;
        Exception var15;
        String var16;
        gh.a var17;
        label64: {
            gh.a var13;
            Exception var10000;
            label74: {
                Object var20 = var18.j;
                Object var7 = ux.b.d();
                var5 = var18.l;
                boolean var10001;
                gh.a var19;
                if (var5 != 0) {
                    if (var5 != 1) {
                        throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                    }

                    var3 = (String)var18.i;
                    var19 = (gh.a)var18.h;
                    var13 = var19;
                    var12 = var3;

                    try {
                        o.b(var20);
                    } catch (Exception var11) {
                        var10000 = var11;
                        var10001 = false;
                        break label74;
                    }
                } else {
                    o.b(var20);
                    kh.a var14 = this.i(var2, var3);
                    if (!(var14 instanceof kh.a.g)) {
                        return null;
                    }

                    bh.e.l(this.g, var3);

                    try {
                        var16 = ((kh.a.g)var14).a();
                        var18.h = this;
                        var18.i = var3;
                        var18.l = 1;
                        var20 = this.j(var1, var16, var3, var18);
                    } catch (Exception var9) {
                        var15 = var9;
                        var12 = var3;
                        var17 = this;
                        break label64;
                    }

                    if (var20 == var7) {
                        return var7;
                    }

                    var19 = this;
                }

                var13 = var19;
                var12 = var3;

                Request var24;
                try {
                    var24 = (Request)var20;
                } catch (Exception var10) {
                    var10000 = var10;
                    var10001 = false;
                    break label74;
                }

                if (var24 != null) {
                    var13 = var19;
                    var12 = var3;

                    try {
                        bh.e.m(var19.g, var3);
                    } catch (Exception var8) {
                        var10000 = var8;
                        var10001 = false;
                        break label74;
                    }
                }

                return var24;
            }

            Exception var21 = var10000;
            var17 = var13;
            var15 = var21;
        }

        l10.a.b var25 = l10.a.a;
        StringBuilder var22 = new StringBuilder();
        var22.append("Assertion_");
        var22.append(var12);
        var25.w(var22.toString()).e(var15);
        c var23 = var17.g;
        var3 = var15.getClass().getName();
        var16 = var15.getMessage();
        StringBuilder var26 = new StringBuilder();
        var26.append(var3);
        var26.append(" ");
        var26.append(var16);
        bh.e.k(var23, var12, var26.toString());
        return null;
    }

    public static final class a {
        private a() {
        }
    }
}
