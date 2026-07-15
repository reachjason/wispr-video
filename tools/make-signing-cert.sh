#!/bin/bash
# Creates a stable, self-signed code-signing identity ("Wispr Video Dev") in a
# dedicated keychain so the app keeps the SAME signature across rebuilds — which
# lets macOS remember granted permissions (Camera / Mic / Screen Recording)
# instead of re-prompting every build. Local dev only; runs without GUI prompts.
set -euo pipefail

IDENTITY="Wispr Video Dev"
KEYCHAIN="wispr-signing.keychain"
KEYCHAIN_DB="$HOME/Library/Keychains/${KEYCHAIN}-db"
KEYCHAIN_PASS="wisprdev"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✅ Signing identity '$IDENTITY' already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▶ Creating dedicated keychain…"
if [ ! -f "$KEYCHAIN_DB" ]; then
    security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
fi
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # disable auto-lock timeout

echo "▶ Generating self-signed code-signing certificate…"
cat > "$TMP/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Wispr Video Dev
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -config "$TMP/openssl.cnf" -extensions v3 >/dev/null 2>&1

openssl pkcs12 -export -name "$IDENTITY" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/ident.p12" \
    -passout pass:"$KEYCHAIN_PASS" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1

echo "▶ Importing into keychain…"
security import "$TMP/ident.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASS" \
    -T /usr/bin/codesign -A

# Authorize codesign to use the private key without GUI prompts.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "▶ Adding keychain to the search list…"
paths=()
while IFS= read -r line; do
    p="$(echo "$line" | tr -d ' "')"
    [ -n "$p" ] && paths+=("$p")
done < <(security list-keychains -d user)
found=0
for p in "${paths[@]}"; do [[ "$p" == *wispr-signing* ]] && found=1; done
if [ $found -eq 0 ]; then paths+=("$KEYCHAIN_DB"); fi
security list-keychains -d user -s "${paths[@]}"

echo ""
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "✅ Created signing identity '$IDENTITY'."
else
    echo "⚠️  Identity created but not listed as valid; codesign may still use it by name."
fi
