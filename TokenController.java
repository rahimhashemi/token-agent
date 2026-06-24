package ir.bankmellat.token.controller;

import ir.bankmellat.token.service.Pkcs11Service;
import ir.bankmellat.token.service.Pkcs11Service.CertificateInfo;
import ir.bankmellat.token.service.Pkcs11Service.PinVerifyResult;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/token")
public class TokenController {

    private final Pkcs11Service pkcs11;

    public TokenController(Pkcs11Service pkcs11) {
        this.pkcs11 = pkcs11;
    }

    // ── GET /api/token/detect ──────────────────────────────────────────────
    // React polls this to show "Insert your token" UI
    @GetMapping("/detect")
    public ResponseEntity<Map<String, Object>> detect() {
        boolean present = pkcs11.isTokenPresent();
        return ResponseEntity.ok(Map.of(
            "present", present,
            "message", present ? "Token detected" : "No token inserted"
        ));
    }

    // ── GET /api/token/certificates ───────────────────────────────────────
    // Returns cert metadata (no PIN required)
    @GetMapping("/certificates")
    public ResponseEntity<?> certificates() {
        try {
            List<CertificateInfo> certs = pkcs11.listCertificates();
            if (certs.isEmpty()) {
                return ResponseEntity.ok(Map.of(
                    "certificates", List.of(),
                    "message", "No certificates found on token"
                ));
            }
            return ResponseEntity.ok(Map.of("certificates", certs));
        } catch (Exception e) {
            return ResponseEntity.status(503).body(Map.of(
                "error", "Could not read token",
                "detail", e.getMessage()
            ));
        }
    }

    // ── POST /api/token/verify-pin ────────────────────────────────────────
    // Validates PIN; PIN is received over HTTPS localhost and never logged
    @PostMapping("/verify-pin")
    public ResponseEntity<Map<String, Object>> verifyPin(
            @RequestBody PinRequest body) {

        if (body.pin() == null || body.pin().isBlank()) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", "PIN must not be empty"
            ));
        }

        PinVerifyResult result = pkcs11.verifyPin(body.pin());

        if (result.success()) {
            return ResponseEntity.ok(Map.of(
                "success", true,
                "certCount", result.certCount(),
                "message", "PIN verified"
            ));
        } else {
            return ResponseEntity.status(401).body(Map.of(
                "success", false,
                "error", result.errorMessage()
            ));
        }
    }

    public record PinRequest(String pin) {}
}
