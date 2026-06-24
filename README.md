# BankMellat ePass Token Agent

Local HTTPS bridge between the React portal (`biz.bankmellat.ir`) and the ePass3003 hardware token via PKCS#11. Replaces the old JNLP/Java Web Start integration.

---

## Architecture

```
Browser (React)
    │  fetch("https://localhost:7070/api/token/...")
    ▼
Local Agent (Spring Boot fat JAR)          ← runs on user's machine
    │  SunPKCS11 provider
    ▼
ePass3003 PKCS#11 library (.dll / .so)
    │
    ▼
ePass3003 USB Token
```

---

## Project Structure

```
epass-agent/
├── agent/                        ← Spring Boot fat JAR
│   └── src/main/
│       ├── java/ir/bankmellat/token/
│       │   ├── TokenAgentApplication.java
│       │   ├── config/
│       │   │   ├── SecurityConfig.java       ← CORS + Origin guard
│       │   │   └── OriginValidationFilter.java
│       │   ├── controller/
│       │   │   └── TokenController.java      ← REST endpoints
│       │   └── service/
│       │       └── Pkcs11Service.java        ← PKCS#11 operations
│       └── resources/
│           ├── application.yml               ← HTTPS + loopback config
│           └── useTokenAgent.ts              ← React hook (copy to frontend)
│
└── installer/
    ├── installer.nsi                         ← NSIS Windows installer
    ├── cert/
    │   └── generate-ca.sh                   ← Run ONCE to generate certs
    ├── scripts/
    │   └── firefox-ca-install.ps1           ← Firefox CA trust setup
    └── resources/                           ← Populated by generate-ca.sh
        ├── bankmellat-ca.crt
        ├── agent-keystore.p12
        └── token-agent-1.0.0.jar
```

---

## Build Steps

### 1. Generate Certificates (one-time, done by your team)

```bash
cd installer/cert
chmod +x generate-ca.sh
./generate-ca.sh

# Copy outputs to installer/resources/cert/
cp bankmellat-ca.crt    ../resources/cert/
cp agent-keystore.p12   ../resources/cert/
```

> ⚠️ Store `bankmellat-ca.key` (Root CA private key) in a **secure offline vault**.
> Never include it in the installer.

### 2. Build the Fat JAR

```bash
cd agent
mvn clean package -DskipTests

# Output: target/token-agent-1.0.0.jar
cp target/token-agent-1.0.0.jar ../installer/resources/
```

### 3. Build the Windows Installer

```bash
cd installer
# Requires NSIS 3.x installed
makensis installer.nsi

# Output: BankMellatTokenAgentSetup.exe
```

---

## What the Installer Does

| Step | Action |
|------|--------|
| 1 | Copies JAR + bundled JRE 21 to `C:\Program Files\BankMellat\TokenAgent` |
| 2 | Installs `bankmellat-ca.crt` into Windows Root CA store → trusted by Chrome & Edge |
| 3 | Installs CA into Firefox via enterprise policy or NSS certutil |
| 4 | Registers agent as a Windows Service (auto-starts on boot) |
| 5 | Starts the service immediately |

---

## API Endpoints

All endpoints only accessible from `https://localhost:7070`. Requests from any origin other than `https://biz.bankmellat.ir` are blocked with HTTP 403.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/token/detect` | None | Is token physically inserted? |
| `GET` | `/api/token/certificates` | None | List certs on token (no PIN) |
| `POST` | `/api/token/verify-pin` | None | Verify PIN; body: `{"pin":"1234"}` |
| `GET` | `/actuator/health` | None | Service health check |

---

## React Integration

Copy `useTokenAgent.ts` into your frontend:

```tsx
import { useTokenAgent } from './useTokenAgent';

function TokenPanel() {
  const { status, verifyPin, loadCertificates } = useTokenAgent();

  if (status === 'agent_offline') {
    return <p>Please install the BankMellat Token Agent first.</p>;
  }

  if (status === 'not_detected') {
    return <p>Please insert your ePass3003 token.</p>;
  }

  return <PinEntry onSubmit={verifyPin} />;
}
```

---

## Security Properties

| Property | How |
|----------|-----|
| Only accessible from localhost | `server.address=127.0.0.1` |
| Only callable by our portal | Origin header validation (HTTP 403 otherwise) |
| Transport encrypted | TLS 1.2/1.3 with our own CA |
| PIN never logged | Scrubbed before any log output |
| PIN never sent to backend | Only signature result goes to Spring Boot |
| Token locked on wrong PIN | PKCS#11 handles lockout natively |

---

## Certificate Renewal

The localhost cert is valid for ~2 years. Renew before expiry:

```bash
# Re-run generate-ca.sh (reuse the same CA key to avoid re-installing CA)
./generate-ca.sh

# Re-build JAR and push new installer version
```

The Root CA is valid for 10 years. Treat its private key like a HSM secret.
