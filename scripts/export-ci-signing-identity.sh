#!/usr/bin/env bash
# Generate a fresh self-signed code signing identity for CI, export it as a
# password-protected p12, and print base64-encoded payloads ready to paste into
# GitHub Secrets. This identity is independent of the developer's local
# `Glossa Local Dev Code Signing` identity — keeping CI and dev separate limits
# the blast radius if either is leaked.
#
# Usage:
#   scripts/export-ci-signing-identity.sh [identity-name]
#
# Output:
#   - prints the three values you need to add as repository secrets:
#       MACOS_SIGNING_CERTIFICATE_P12_BASE64
#       MACOS_SIGNING_CERTIFICATE_PASSWORD
#       MACOS_SIGNING_IDENTITY
#   - prints recommended MACOS_KEYCHAIN_PASSWORD (any value works; we generate
#     a strong one for you)
#
# The p12 file is left on disk at the printed path so you can re-paste it into
# GitHub if needed; delete it once the secrets are uploaded.

set -euo pipefail

IDENTITY_NAME="${1:-LocalTypeless CI Code Signing}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required." >&2
  exit 1
fi
if ! command -v base64 >/dev/null 2>&1; then
  echo "base64 is required." >&2
  exit 1
fi

OUT_DIR="${TMPDIR:-/tmp}/local-typeless-ci-signing.$$"
mkdir -p "${OUT_DIR}"

CONFIG="${OUT_DIR}/codesign.cnf"
KEY="${OUT_DIR}/identity.key"
CERT="${OUT_DIR}/identity.cer"
P12="${OUT_DIR}/identity.p12"
P12_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)"

cat >"${CONFIG}" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions    = codesign
prompt             = no

[ req_distinguished_name ]
CN = ${IDENTITY_NAME}

[ codesign ]
basicConstraints       = critical, CA:true
keyUsage               = critical, digitalSignature, keyCertSign
extendedKeyUsage       = codeSigning
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

openssl req \
  -new -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes \
  -keyout "${KEY}" -out "${CERT}" \
  -subj "/CN=${IDENTITY_NAME}" \
  -config "${CONFIG}" -extensions codesign >/dev/null 2>&1

# `-legacy` only exists on OpenSSL 3.x and tells it to fall back to the
# RC2/3DES algorithms macOS's `security import` is most lenient about.
# LibreSSL (macOS's bundled openssl at /usr/bin/openssl) doesn't have the
# flag and already defaults to that format.
PKCS12_LEGACY=()
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
  PKCS12_LEGACY=(-legacy)
fi

openssl pkcs12 \
  -export ${PKCS12_LEGACY[@]+"${PKCS12_LEGACY[@]}"} \
  -inkey "${KEY}" -in "${CERT}" \
  -out "${P12}" \
  -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1

P12_BASE64="$(base64 -i "${P12}" | tr -d '\n')"

cat <<EOF

Generated CI signing identity:  ${IDENTITY_NAME}
P12 file kept at:               ${P12}

Paste these values as GitHub repository secrets
(Settings → Secrets and variables → Actions → New repository secret):

  MACOS_SIGNING_IDENTITY                  = ${IDENTITY_NAME}
  MACOS_SIGNING_CERTIFICATE_PASSWORD      = ${P12_PASSWORD}
  MACOS_KEYCHAIN_PASSWORD                 = ${KEYCHAIN_PASSWORD}

  MACOS_SIGNING_CERTIFICATE_P12_BASE64    =
${P12_BASE64}

After uploading the secrets, remove the working copy:

  rm -rf "${OUT_DIR}"

EOF
