#!/bin/bash
# ============================================================
# BankMellat ePass Agent — Root CA + Localhost Cert Generator
# Run once during build; outputs go into installer/resources/
# ============================================================
set -e

OUT="$(dirname "$0")"
CA_KEY="$OUT/bankmellat-ca.key"
CA_CERT="$OUT/bankmellat-ca.crt"
SERVER_KEY="$OUT/localhost.key"
SERVER_CSR="$OUT/localhost.csr"
SERVER_CERT="$OUT/localhost.crt"
SERVER_P12="$OUT/agent-keystore.p12"
CA_P12="$OUT/bankmellat-ca.p12"

VALIDITY_CA=3650    # 10 years
VALIDITY_CERT=825   # ~2.25 years (Chrome max)
CA_PASSWORD="BankMellatCA2024!"
KS_PASSWORD="AgentKeystore2024!"

echo "──────────────────────────────────────────"
echo " Step 1: Generate Root CA key & certificate"
echo "──────────────────────────────────────────"
openssl genrsa -out "$CA_KEY" 4096

openssl req -new -x509 \
  -key "$CA_KEY" \
  -out "$CA_CERT" \
  -days $VALIDITY_CA \
  -subj "/C=IR/ST=Tehran/L=Tehran/O=Bank Mellat/OU=IT Security/CN=BankMellat Token Agent CA" \
  -extensions v3_ca \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"

echo "✅ Root CA generated: $CA_CERT"

echo "──────────────────────────────────────────"
echo " Step 2: Generate localhost server key & CSR"
echo "──────────────────────────────────────────"
openssl genrsa -out "$SERVER_KEY" 2048

openssl req -new \
  -key "$SERVER_KEY" \
  -out "$SERVER_CSR" \
  -subj "/C=IR/ST=Tehran/L=Tehran/O=Bank Mellat/OU=Token Agent/CN=localhost"

echo "──────────────────────────────────────────"
echo " Step 3: Sign server cert with Root CA"
echo "──────────────────────────────────────────"

# SAN extension config (required by Chrome/Edge)
cat > /tmp/localhost-ext.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
basicConstraints = CA:FALSE
[alt_names]
DNS.1 = localhost
IP.1  = 127.0.0.1
EOF

openssl x509 -req \
  -in "$SERVER_CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$SERVER_CERT" \
  -days $VALIDITY_CERT \
  -sha256 \
  -extfile /tmp/localhost-ext.cnf \
  -extensions v3_req

echo "✅ Server certificate signed: $SERVER_CERT"

echo "──────────────────────────────────────────"
echo " Step 4: Package into PKCS#12 keystores"
echo "──────────────────────────────────────────"

# Agent keystore (used by Spring Boot)
openssl pkcs12 -export \
  -in "$SERVER_CERT" \
  -inkey "$SERVER_KEY" \
  -certfile "$CA_CERT" \
  -out "$SERVER_P12" \
  -name "agent-localhost" \
  -passout "pass:$KS_PASSWORD"

echo "✅ Agent keystore: $SERVER_P12 (password: $KS_PASSWORD)"

# CA-only PKCS12 for Firefox import
openssl pkcs12 -export \
  -in "$CA_CERT" \
  -nokeys \
  -out "$CA_P12" \
  -passout "pass:$CA_PASSWORD"

echo "✅ CA PKCS12 for Firefox: $CA_P12"
echo ""
echo "📁 Copy these files to installer/resources/:"
echo "   - bankmellat-ca.crt  (install into OS trust store)"
echo "   - bankmellat-ca.p12  (import into Firefox)"
echo "   - agent-keystore.p12 (bundled inside the jar)"
