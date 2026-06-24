package ir.bankmellat.token.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.security.KeyStore;
import java.security.Provider;
import java.security.Security;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;

@Service
public class Pkcs11Service {

    private static final Logger log = LoggerFactory.getLogger(Pkcs11Service.class);

    @Value("${agent.pkcs11.windows-library}")
    private String windowsLib;

    @Value("${agent.pkcs11.linux-library}")
    private String linuxLib;

    @Value("${agent.pkcs11.mac-library}")
    private String macLib;

    // ── Token Detection ────────────────────────────────────────────────────

    public boolean isTokenPresent() {
        try {
            Provider p = buildProvider();
            KeyStore ks = KeyStore.getInstance("PKCS11", p);
            // Load without PIN — just checks if token is physically inserted
            ks.load(null, null);
            return true;
        } catch (Exception e) {
            log.debug("Token not detected: {}", e.getMessage());
            return false;
        }
    }

    // ── Certificate Reading (no PIN needed) ───────────────────────────────

    public List<CertificateInfo> listCertificates() throws Exception {
        Provider p = buildProvider();
        KeyStore ks = KeyStore.getInstance("PKCS11", p);
        ks.load(null, null);   // Read cert metadata without PIN

        List<CertificateInfo> result = new ArrayList<>();
        Enumeration<String> aliases = ks.aliases();

        while (aliases.hasMoreElements()) {
            String alias = aliases.nextElement();
            if (ks.isCertificateEntry(alias) || ks.isKeyEntry(alias)) {
                X509Certificate cert = (X509Certificate) ks.getCertificate(alias);
                if (cert != null) {
                    result.add(CertificateInfo.from(alias, cert));
                }
            }
        }
        return result;
    }

    // ── PIN Verification ──────────────────────────────────────────────────

    /**
     * Verifies the PIN by loading the private key — does NOT return the key.
     * Throws on wrong PIN or locked token.
     */
    public PinVerifyResult verifyPin(String pin) {
        try {
            Provider p = buildProvider();
            KeyStore ks = KeyStore.getInstance("PKCS11", p);
            ks.load(null, pin.toCharArray());   // This validates the PIN

            // Just enumerate to confirm access
            Enumeration<String> aliases = ks.aliases();
            int count = 0;
            while (aliases.hasMoreElements()) {
                aliases.nextElement();
                count++;
            }

            return new PinVerifyResult(true, count, null);

        } catch (Exception e) {
            String msg = e.getMessage();
            log.warn("PIN verification failed: {}", msg);

            // Detect common PKCS#11 error codes
            if (msg != null && msg.contains("CKR_PIN_INCORRECT")) {
                return new PinVerifyResult(false, 0, "PIN incorrect");
            }
            if (msg != null && msg.contains("CKR_PIN_LOCKED")) {
                return new PinVerifyResult(false, 0, "Token is locked — contact your administrator");
            }
            if (msg != null && msg.contains("CKR_TOKEN_NOT_PRESENT")) {
                return new PinVerifyResult(false, 0, "Token not inserted");
            }
            return new PinVerifyResult(false, 0, "Verification failed: " + msg);
        }
    }

    // ── Internal: Build PKCS#11 Provider ──────────────────────────────────

    private Provider buildProvider() {
        String library = detectLibraryPath();
        String config = String.format("""
            name = ePass3003
            library = %s
            slot = 0
            """, library);

        // Use SunPKCS11 (bundled in JDK 9+)
        Provider base = Security.getProvider("SunPKCS11");
        if (base == null) {
            throw new IllegalStateException("SunPKCS11 provider not available. Use JDK 9+.");
        }
        return base.configure(config);
    }

    private String detectLibraryPath() {
        String os = System.getProperty("os.name").toLowerCase();
        if (os.contains("win"))   return windowsLib;
        if (os.contains("mac"))   return macLib;
        return linuxLib;
    }

    // ── Inner DTOs ─────────────────────────────────────────────────────────

    public record PinVerifyResult(boolean success, int certCount, String errorMessage) {}

    public record CertificateInfo(
        String alias,
        String subject,
        String issuer,
        String serialNumber,
        String notBefore,
        String notAfter
    ) {
        public static CertificateInfo from(String alias, X509Certificate cert) {
            return new CertificateInfo(
                alias,
                cert.getSubjectX500Principal().getName(),
                cert.getIssuerX500Principal().getName(),
                cert.getSerialNumber().toString(16).toUpperCase(),
                cert.getNotBefore().toInstant().toString(),
                cert.getNotAfter().toInstant().toString()
            );
        }
    }
}
