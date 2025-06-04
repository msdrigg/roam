//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
//

package ep;

import android.util.Base64;
import dy.x;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.Signature;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import kotlin.collections.l;

public final class a {
    private static final char[] a;

    static {
        char[] var0 = "0123456789abcdef".toCharArray();
        x.h(var0, "this as java.lang.String).toCharArray()");
        a = var0;
    }

    public static final byte[] a(byte[] var0) {
        x.i(var0, "<this>");

        try {
            MessageDigest var1 = MessageDigest.getInstance("SHA-256");
            var1.update(var0);
            var0 = var1.digest();
        } catch (NoSuchAlgorithmException var2) {
            l10.a.a.e(var2);
            var0 = null;
        }

        return var0;
    }

    public static final byte[] b(byte[] var0, String var1) {
        x.i(var1, "data");
        Object var2 = null;

        try {
            Mac var3 = Mac.getInstance("HmacSHA256");
            SecretKeySpec var4 = new SecretKeySpec(var0, "HmacSHA256");
            var3.init(var4);
            Charset var7 = StandardCharsets.UTF_8;
            x.h(var7, "UTF_8");
            var0 = var1.getBytes(var7);
            x.h(var0, "this as java.lang.String).getBytes(charset)");
            var0 = var3.doFinal(var0);
        } catch (NoSuchAlgorithmException var5) {
            l10.a.a.e(var5);
            var0 = (byte[])var2;
        } catch (InvalidKeyException var6) {
            l10.a.a.e(var6);
            var0 = (byte[])var2;
        }

        return var0;
    }

    public static final byte[] c(byte[] var0, String var1, PrivateKey var2) {
        x.i(var0, "<this>");
        x.i(var1, "yourAlgorithm");
        x.i(var2, "privateKey");
        Signature var3 = Signature.getInstance(var1);
        var3.initSign(var2);
        var3.update(var0);
        var0 = var3.sign();
        x.h(var0, "sign()");
        return var0;
    }

    public static final byte[] d(byte[] data, String algorithm = "SHA256withRSA", PrivateKey privateKey) {
        return c(data, algorithm, privateKey)
    }

    public static final String e(byte[] var0) {
        x.i(var0, "<this>");
        String var1 = Base64.encodeToString(var0, 2);
        x.h(var1, "encodeToString(this, Base64.NO_WRAP)");
        return var1;
    }

    public static final String f(byte[] var0) {
        if (var0 != null) {
            int var1 = var0.length;
            int var2 = 0;
            boolean var8;
            if (var1 == 0) {
                var8 = true;
            } else {
                var8 = false;
            }

            if (!var8) {
                char[] var7 = new char[var0.length * 2];
                int var3 = var0.length;

                for(var1 = 0; var2 < var3; ++var1) {
                    int var4 = var0[var2] & 255;
                    int var5 = var1 * 2;
                    char[] var6 = a;
                    var7[var5] = var6[var4 / 16];
                    var7[var5 + 1] = var6[var4 % 16];
                    ++var2;
                }

                return l.q0(var7, "", (CharSequence)null, (CharSequence)null, 0, (CharSequence)null, (cy.l)null, 62, (Object)null);
            }
        }

        return "";
    }
}