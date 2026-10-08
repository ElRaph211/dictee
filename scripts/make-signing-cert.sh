#!/bin/bash
# Crée une identité de signature locale auto-signée « Dictee Local Signing » dans le trousseau de session.
# Pourquoi : une app signée ad hoc change d'empreinte à chaque build, et macOS oublie alors les
# autorisations Accessibilité / Surveillance de l'entrée. Avec ce certificat, l'exigence de code
# devient stable (identifier + certificat) et les autorisations survivent aux mises à jour.
# Rien n'est envoyé nulle part ; clé privée dans le trousseau de session uniquement.
set -euo pipefail
NAME="Dictee Local Signing"
if security find-certificate -c "$NAME" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
  echo "Identité « $NAME » déjà présente."
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:dictee -name "$NAME" 2>/dev/null
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P dictee -T /usr/bin/codesign -T /usr/bin/security -A
echo "Identité « $NAME » créée (valable 10 ans)."
