#!/usr/bin/env bash
set -euo pipefail

# Provisions a stable self-signed codesigning cert in the login keychain so
# that locally rebuilt MuesliDev binaries keep their TCC permissions
# (Accessibility, Screen Recording, Input Monitoring) across rebuilds.
#
# Without a stable identity the build falls back to adhoc, which derives the
# identity from the binary's content hash. Every rebuild then looks like a
# different app to TCC, invalidating prior permission grants.
#
# Idempotent: re-running with the cert already in place is a no-op.

CERT_NAME="${MUESLI_DEV_CERT_NAME:-MuesliDev Self Signed}"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
VALIDITY_DAYS="${MUESLI_DEV_CERT_DAYS:-3650}"

if security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" \
   | grep -Fq "\"$CERT_NAME\""; then
  exit 0
fi

echo "Creating self-signed codesigning cert: $CERT_NAME"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

KEY="$WORK/key.pem"
CRT="$WORK/cert.pem"
P12="$WORK/cert.p12"

cat > "$WORK/req.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_codesign
[dn]
CN = $CERT_NAME
[v3_codesign]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CRT" \
  -days "$VALIDITY_DAYS" -nodes -config "$WORK/req.cnf" >/dev/null 2>&1

openssl pkcs12 -export -in "$CRT" -inkey "$KEY" \
  -out "$P12" -name "$CERT_NAME" -passout pass: >/dev/null 2>&1

security import "$P12" -k "$LOGIN_KEYCHAIN" -P "" -T /usr/bin/codesign >/dev/null

if [[ -n "${MUESLI_DEV_CERT_LOGIN_PASSWORD:-}" ]]; then
  security set-key-partition-list -S apple-tool:,apple: \
    -s -k "$MUESLI_DEV_CERT_LOGIN_PASSWORD" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true
fi

cat <<'EOF'
  Cert imported into login keychain.

  The first time codesign uses it, macOS may show a Keychain prompt
  ("codesign wants to use key …"). Click "Always Allow" once.

  To verify: security find-identity -v -p codesigning
EOF
