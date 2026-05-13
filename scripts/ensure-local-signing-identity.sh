#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${1:-${LOCAL_TYPELESS_CODE_SIGN_IDENTITY:-Glossa Local Dev Code Signing}}"

if security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"${IDENTITY_NAME}\""; then
  echo "Using existing codesigning identity: ${IDENTITY_NAME}"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to create a local signing identity." >&2
  exit 1
fi

KEYCHAIN="$(security default-keychain -d user | tr -d '"')"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

CONFIG="${TMPDIR}/codesign.cnf"
KEY="${TMPDIR}/identity.key"
CERT="${TMPDIR}/identity.cer"
P12="${TMPDIR}/identity.p12"
P12_PASSWORD="$(uuidgen)"

cat >"${CONFIG}" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = codesign
prompt = no

[ req_distinguished_name ]
CN = ${IDENTITY_NAME}

[ codesign ]
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

echo "Creating local codesigning identity: ${IDENTITY_NAME}"
openssl req \
  -new \
  -newkey rsa:2048 \
  -x509 \
  -sha256 \
  -days 3650 \
  -nodes \
  -keyout "${KEY}" \
  -out "${CERT}" \
  -subj "/CN=${IDENTITY_NAME}" \
  -config "${CONFIG}" \
  -extensions codesign >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -inkey "${KEY}" \
  -in "${CERT}" \
  -out "${P12}" \
  -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1

security import "${P12}" \
  -k "${KEYCHAIN}" \
  -P "${P12_PASSWORD}" \
  -A \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "${KEYCHAIN}" \
  "${CERT}" >/dev/null

if ! security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"${IDENTITY_NAME}\""; then
  echo "Created the certificate, but macOS did not expose it as a valid codesigning identity." >&2
  echo "Open Keychain Access and verify that '${IDENTITY_NAME}' has a private key and is trusted for code signing." >&2
  exit 1
fi

echo "Created codesigning identity in keychain: ${IDENTITY_NAME}"
