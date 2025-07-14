//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
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
    private final AttestApi a;
    private final g b;
    private final d c;
    private final c d;
    private final cy.a<String> e;
    private final cy.a<String> f;

    public b(AttestApi var1, g var2, d var3, c var4, cy.a<String> var5, cy.a<String> var6) {
        x.i(var1, "attestApi");
        x.i(var2, "integrityTokenHelper");
        x.i(var3, "attestKeyPairProvider");
        x.i(var4, "analyticsService");
        x.i(var5, "challengeUrl");
        x.i(var6, "registerUrl");
        super();
        this.a = var1;
        this.b = var2;
        this.c = var3;
        this.d = var4;
        this.e = var5;
        this.f = var6;
    }

    public Object E2(kh.a.b var1, String var2, tx.d<? super kh.a> var3) {
        int var4;

        @f(
            c = "com.roku.mobile.attestation.api.AttestRepositoryImpl",
            f = "AttestRepositoryImpl.kt",
            l = {98},
            m = "getChallenge"
        )
        final class NamelessClass_2 extends kotlin.coroutines.jvm.internal.d {
            Object h;
            Object i;
            final b j;
            int k;

            NamelessClass_2(b var1, tx.d<? super NamelessClass_2> var2) {
                super(var2);
                this.j = var1;
            }

            public final Object invokeSuspend(Object var1) {
                this.i = var1;
                this.k |= Integer.MIN_VALUE;
                return this.j.E2((kh.a.b)null, (String)null, this);
            }
        }

        NamelessClass_2 var6;
        label60: {
            if (var3 instanceof NamelessClass_2) {
                var6 = (NamelessClass_2)var3;
                var4 = var6.k;
                if ((var4 & Integer.MIN_VALUE) != 0) {
                    var6.k = var4 + Integer.MIN_VALUE;
                    break label60;
                }
            }

            var6 = new NamelessClass_2(this, var3);
        }

        Object var7 = var6.i;
        Object var9 = ux.b.d();
        var4 = var6.k;
        b var8;
        if (var4 != 0) {
            if (var4 != 1) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }

            var8 = (b)var6.h;
            o.b(var7);
        } else {
            o.b(var7);
            h.d(this.d, "challenge_requested");
            AttestApi var5 = this.a;
            var2 = (String)this.e.invoke();
            var6.h = this;
            var6.k = 1;
            var7 = var5.getChallenge(var2, var6);
            if (var7 == var9) {
                return var9;
            }

            var8 = this;
        }

        zo.b var17 = (zo.b)var7;
        Object var10;
        String var12;
        Integer var14;
        if (zo.f.g(var17)) {
            ChallengeResponse var11 = (ChallengeResponse)zo.f.a(var17);
            if (var11 != null) {
                var2 = var11.a();
                if (var2 != null) {
                    c var15 = var8.d;
                    ChallengeResponse var13 = (ChallengeResponse)zo.f.a(var17);
                    Long var16;
                    if (var13 != null) {
                        var16 = var13.b();
                    } else {
                        var16 = null;
                    }

                    h.e(var15, "challenge_retrieved", var16);
                    var10 = new kh.a.c(var2);
                    return var10;
                }
            }

            var12 = zo.f.d(var17);
            var2 = var12;
            if (var12 == null) {
                var2 = "Challenge field not found";
            }

            var14 = zo.f.b(var17);
            if (var14 != null) {
                var4 = var14;
            } else {
                var4 = -101;
            }

            h.d(var8.d, "challenge_failed");
            var10 = new kh.a.f.b(var2, kotlin.coroutines.jvm.internal.b.d(var4));
        } else {
            var12 = zo.f.d(var17);
            var2 = var12;
            if (var12 == null) {
                var2 = "Challenge API Failed";
            }

            var14 = zo.f.b(var17);
            if (var14 != null) {
                var4 = var14;
            } else {
                var4 = -104;
            }

            h.d(var8.d, "challenge_failed");
            var10 = new kh.a.f.b(var2, kotlin.coroutines.jvm.internal.b.d(var4));
        }

        return var10;
    }

    public Object F2(kh.a.d var1, String var2, String var3, tx.d<? super kh.a> var4) {
        int var5;

        @f(
            c = "com.roku.mobile.attestation.api.AttestRepositoryImpl",
            f = "AttestRepositoryImpl.kt",
            l = {57},
            m = "getChallenge"
        )
        final class NamelessClass_1 extends kotlin.coroutines.jvm.internal.d {
            Object h;
            Object i;
            Object j;
            final b k;
            int l;

            NamelessClass_1(b var1, tx.d<? super NamelessClass_1> var2) {
                super(var2);
                this.k = var1;
            }

            public final Object invokeSuspend(Object var1) {
                this.j = var1;
                this.l |= Integer.MIN_VALUE;
                return this.k.F2((kh.a.d)null, (String)null, (String)null, this);
            }
        }

        NamelessClass_1 var7;
        label60: {
            if (var4 instanceof NamelessClass_1) {
                var7 = (NamelessClass_1)var4;
                var5 = var7.l;
                if ((var5 & Integer.MIN_VALUE) != 0) {
                    var7.l = var5 + Integer.MIN_VALUE;
                    break label60;
                }
            }

            var7 = new NamelessClass_1(this, var4);
        }

        Object var8 = var7.j;
        Object var13 = ux.b.d();
        var5 = var7.l;
        b var9;
        if (var5 != 0) {
            if (var5 != 1) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }

            var3 = (String)var7.i;
            var9 = (b)var7.h;
            o.b(var8);
        } else {
            o.b(var8);
            bh.e.e(this.d, var3);
            AttestApi var6 = this.a;
            var2 = (String)this.e.invoke();
            var7.h = this;
            var7.i = var3;
            var7.l = 1;
            var8 = var6.getChallenge(var2, var7);
            if (var8 == var13) {
                return var13;
            }

            var9 = this;
        }

        zo.b var18 = (zo.b)var8;
        Object var10;
        String var15;
        Integer var16;
        if (zo.f.g(var18)) {
            ChallengeResponse var11 = (ChallengeResponse)zo.f.a(var18);
            if (var11 != null) {
                var2 = var11.a();
                if (var2 != null) {
                    c var17 = var9.d;
                    ChallengeResponse var12 = (ChallengeResponse)zo.f.a(var18);
                    Long var14;
                    if (var12 != null) {
                        var14 = var12.b();
                    } else {
                        var14 = null;
                    }

                    bh.e.f(var17, var3, var14);
                    var10 = new kh.a.c(var2);
                    return var10;
                }
            }

            var15 = zo.f.d(var18);
            var2 = var15;
            if (var15 == null) {
                var2 = "Challenge field not found";
            }

            var16 = zo.f.b(var18);
            if (var16 != null) {
                var5 = var16;
            } else {
                var5 = -101;
            }

            bh.e.d(var9.d, var3, var5, var2);
            var10 = new kh.a.f.b(var2, kotlin.coroutines.jvm.internal.b.d(var5));
        } else {
            var15 = zo.f.d(var18);
            var2 = var15;
            if (var15 == null) {
                var2 = "Challenge API Failed";
            }

            var16 = zo.f.b(var18);
            if (var16 != null) {
                var5 = var16;
            } else {
                var5 = -104;
            }

            bh.e.d(var9.d, var3, var5, var2);
            var10 = new kh.a.f.b(var2, kotlin.coroutines.jvm.internal.b.d(var5));
        }

        return var10;
    }

    public Object G2(kh.a.c var1, String var2, String var3, tx.d<? super kh.a> var4) {
        int var5;

        @f(
            c = "com.roku.mobile.attestation.api.AttestRepositoryImpl",
            f = "AttestRepositoryImpl.kt",
            l = {131, 138},
            m = "register"
        )
        final class NamelessClass_3 extends kotlin.coroutines.jvm.internal.d {
            Object h;
            Object i;
            Object j;
            Object k;
            final b l;
            int m;

            NamelessClass_3(b var1, tx.d<? super NamelessClass_3> var2) {
                super(var2);
                this.l = var1;
            }

            public final Object invokeSuspend(Object var1) {
                this.k = var1;
                this.m |= Integer.MIN_VALUE;
                return this.l.G2((kh.a.c)null, (String)null, (String)null, this);
            }
        }

        NamelessClass_3 var11;
        label69: {
            if (var4 instanceof NamelessClass_3) {
                var11 = (NamelessClass_3)var4;
                var5 = var11.m;
                if ((var5 & Integer.MIN_VALUE) != 0) {
                    var11.m = var5 + Integer.MIN_VALUE;
                    break label69;
                }
            }

            var11 = new NamelessClass_3(this, var4);
        }

        Object var8;
        b var10;
        Object var17;
        label64: {
            var17 = var11.k;
            Object var9 = ux.b.d();
            var5 = var11.m;
            var8 = null;
            String var6;
            Object var7;
            kh.a.c var13;
            if (var5 != 0) {
                if (var5 != 1) {
                    if (var5 != 2) {
                        throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                    }

                    var10 = (b)var11.h;
                    o.b(var17);
                    break label64;
                }

                var6 = (String)var11.j;
                var13 = (kh.a.c)var11.i;
                var10 = (b)var11.h;
                o.b(var17);
                var7 = var17;
            } else {
                o.b(var17);
                d var19 = this.c;
                var11.h = this;
                var11.i = var1;
                var11.j = var3;
                var11.m = 1;
                var7 = fh.d.i(var19, false, var11, 1, (Object)null);
                if (var7 == var9) {
                    return var9;
                }

                var6 = var3;
                var13 = var1;
                var10 = this;
            }

            byte[] var23 = ((PublicKey)var7).getEncoded();
            x.h(var23, "attestKeyPairProvider.getPublicKey().encoded");
            String var25 = ep.a.e(var23);
            AttestationRequest var27 = new AttestationRequest(var6, var13.a(), var25);
            h.d(var10.d, "register_requested");
            AttestApi var18 = var10.a;
            var25 = (String)var10.f.invoke();
            var11.h = var10;
            var11.i = null;
            var11.j = null;
            var11.m = 2;
            var17 = var18.register(var25, var27, var11);
            if (var17 == var9) {
                return var9;
            }
        }

        zo.b var20 = (zo.b)var17;
        String var22;
        Object var26;
        if (zo.f.g(var20)) {
            c var14 = var10.d;
            RegisterResponse var12 = (RegisterResponse)zo.f.a(var20);
            Long var15;
            if (var12 != null) {
                var15 = var12.b();
            } else {
                var15 = null;
            }

            h.e(var14, "register_retrieved", var15);
            var12 = (RegisterResponse)zo.f.a(var20);
            if (var12 != null) {
                var22 = var12.a();
            } else {
                var22 = null;
            }

            RegisterResponse var24 = (RegisterResponse)zo.f.a(var20);
            Long var16 = (Long)var8;
            if (var24 != null) {
                var16 = var24.b();
            }

            var26 = new kh.a.d(var22, var16);
        } else {
            Integer var21 = zo.f.b(var20);
            if (var21 != null && var21 == 435) {
                h.d(var10.d, "register_failed");
                var2 = zo.f.d(var20);
                var22 = var2;
                if (var2 == null) {
                    var22 = "Register integrity failed";
                }

                var26 = new kh.a.f.a(var22);
            } else {
                h.d(var10.d, "register_failed");
                var2 = zo.f.d(var20);
                var22 = var2;
                if (var2 == null) {
                    var22 = "Register API Failed";
                }

                var26 = new kh.a.f.b(var22, zo.f.b(var20));
            }
        }

        return var26;
    }

    public Object Q(kh.a.d var1, String var2, String var3, tx.d<? super kh.a> var4) {
        int var5;

        @f(
            c = "com.roku.mobile.attestation.api.AttestRepositoryImpl",
            f = "AttestRepositoryImpl.kt",
            l = {196},
            m = "requestAssertion"
        )
        final class NamelessClass_4 extends kotlin.coroutines.jvm.internal.d {
            Object h;
            final b i;
            int j;

            NamelessClass_4(b var1, tx.d<? super NamelessClass_4> var2) {
                super(var2);
                this.i = var1;
            }

            public final Object invokeSuspend(Object var1) {
                this.h = var1;
                this.j |= Integer.MIN_VALUE;
                return this.i.Q((kh.a.d)null, (String)null, (String)null, this);
            }
        }

        NamelessClass_4 var11;
        label27: {
            if (var4 instanceof NamelessClass_4) {
                NamelessClass_4 var6 = (NamelessClass_4)var4;
                var5 = var6.j;
                if ((var5 & Integer.MIN_VALUE) != 0) {
                    var6.j = var5 + Integer.MIN_VALUE;
                    var11 = var6;
                    break label27;
                }
            }

            var11 = new NamelessClass_4(this, var4);
        }

        Object var12 = var11.h;
        Object var7 = ux.b.d();
        var5 = var11.j;
        Object var8;
        if (var5 != 0) {
            if (var5 != 1) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }

            o.b(var12);
            var8 = var12;
        } else {
            o.b(var12);
            var11.j = 1;
            Object var9 = this.F2(var1, var2, var3, var11);
            var8 = var9;
            if (var9 == var7) {
                return var7;
            }
        }

        kh.a var10 = (kh.a)var8;
        var8 = var10;
        if (var10 instanceof kh.a.c) {
            var8 = new kh.a.g(((kh.a.c)var10).a());
        }

        return var8;
    }

    public Object f1(kh.a.b var1, String var2, tx.d<? super kh.a> var3) {
        int var4;

        @f(
            c = "com.roku.mobile.attestation.api.AttestRepositoryImpl",
            f = "AttestRepositoryImpl.kt",
            l = {172, 177, 179},
            m = "requestAttestation"
        )
        final class NamelessClass_5 extends kotlin.coroutines.jvm.internal.d {
            Object h;
            Object i;
            Object j;
            Object k;
            final b l;
            int m;

            NamelessClass_5(b var1, tx.d<? super NamelessClass_5> var2) {
                super(var2);
                this.l = var1;
            }

            public final Object invokeSuspend(Object var1) {
                this.k = var1;
                this.m |= Integer.MIN_VALUE;
                return this.l.f1((kh.a.b)null, (String)null, this);
            }
        }

        NamelessClass_5 var5;
        label57: {
            if (var3 instanceof NamelessClass_5) {
                var5 = (NamelessClass_5)var3;
                var4 = var5.m;
                if ((var4 & Integer.MIN_VALUE) != 0) {
                    var5.m = var4 + Integer.MIN_VALUE;
                    break label57;
                }
            }

            var5 = new NamelessClass_5(this, var3);
        }

        Object var11;
        label60: {
            kh.a var6;
            Object var8;
            b var9;
            label61: {
                var11 = var5.k;
                var8 = ux.b.d();
                var4 = var5.m;
                if (var4 != 0) {
                    if (var4 != 1) {
                        if (var4 != 2) {
                            if (var4 != 3) {
                                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                            }

                            o.b(var11);
                            break label60;
                        }

                        var6 = (kh.a)var5.j;
                        var2 = (String)var5.i;
                        var9 = (b)var5.h;
                        o.b(var11);
                        break label61;
                    }

                    var2 = (String)var5.i;
                    var9 = (b)var5.h;
                    o.b(var11);
                } else {
                    o.b(var11);
                    var5.h = this;
                    var5.i = var2;
                    var5.m = 1;
                    var11 = this.E2(var1, var2, var5);
                    if (var11 == var8) {
                        return var8;
                    }

                    var9 = this;
                }

                var6 = (kh.a)var11;
                var11 = var6;
                if (!(var6 instanceof kh.a.c)) {
                    return var11;
                }

                g var7 = var9.b;
                String var12 = ((kh.a.c)var6).a();
                var5.h = var9;
                var5.i = var2;
                var5.j = var6;
                var5.m = 2;
                Object var15 = var7.h(var12, var5);
                var11 = var15;
                if (var15 == var8) {
                    return var8;
                }
            }

            g.b var16 = (g.b)var11;
            if (!(var16 instanceof g.b.b)) {
                if (!(var16 instanceof g.b.a)) {
                    throw new NoWhenBranchMatchedException();
                }

                var11 = new kh.a.a.b(((g.b.a)var16).a());
                return var11;
            }

            kh.a.c var13 = (kh.a.c)var6;
            String var14 = ((g.b.b)var16).a();
            var5.h = null;
            var5.i = null;
            var5.j = null;
            var5.m = 3;
            Object var10 = var9.G2(var13, var2, var14, var5);
            var11 = var10;
            if (var10 == var8) {
                return var8;
            }
        }

        var11 = (kh.a)var11;
        return var11;
    }
}
