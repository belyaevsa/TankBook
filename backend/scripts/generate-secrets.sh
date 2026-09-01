#!/usr/bin/env bash
# Generates the production secrets that have no other source, and prints the ONE
# public value that has to be carried into the iOS bundle.
#
#   bash backend/scripts/generate-secrets.sh              # print, for copy into GitHub Secrets
#   bash backend/scripts/generate-secrets.sh --gh-set     # also `gh secret set` each one
#
# What it produces, and why each is generated rather than chosen:
#
#   CONFIG_SIGNING_KEY    A 32-byte Ed25519 seed, base64. Signs the remote config
#                         document; the app verifies against a public key compiled
#                         into the binary. This script also prints that PUBLIC key
#                         and its keyId, derived exactly as `ConfigSigner` does
#                         (raw 32-byte public key, base64; keyId = first 16 hex
#                         chars of its SHA-256). The public half goes into
#                         ConfigSigningKey.swift's RELEASE arm.
#   TANKBOOK_HASH_SALT    The pepper for the accountHash in logs (docs/LOGGING.md).
#   AUTH_JWT_SIGNING_KEY  PKCS#8 RSA-2048 private key, base64, for access tokens.
#
# CATALOG_ADMIN_TOKEN is deliberately absent: catalog packs are written directly
# to the database (2026-09-01), and the publish endpoint it gated is gone.
#
# NOTHING IS WRITTEN TO DISK. These values are printed once; put them in the
# platform secret store and in GitHub Secrets, and do not commit them. Re-running
# this produces DIFFERENT keys - rotating CONFIG_SIGNING_KEY invalidates every
# shipped app's bundled public key until a build carries the new one, and
# rotating TANKBOOK_HASH_SALT re-anonymises every account id so old log lines
# stop correlating with new ones.
set -euo pipefail

gh_set=false
[ "${1:-}" = "--gh-set" ] && gh_set=true

emit() {
    local name="$1" value="$2"
    if [ "${gh_set}" = true ]; then
        printf '%s' "${value}" | gh secret set "${name}" >/dev/null
        echo "  ${name} -> set in GitHub Secrets (${#value} chars)"
    else
        echo "${name}=${value}"
    fi
}

config_seed="$(python3 -c '
import base64, os
print(base64.b64encode(os.urandom(32)).decode())')"

hash_salt="$(python3 -c '
import base64, os
print(base64.b64encode(os.urandom(32)).decode())')"

jwt_key="$(python3 -c '
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
import base64
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
der = key.private_bytes(
    encoding=serialization.Encoding.DER,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption())
print(base64.b64encode(der).decode())')"

echo "# Secrets - store these, they are printed once and never written to disk."
emit CONFIG_SIGNING_KEY "${config_seed}"
emit TANKBOOK_HASH_SALT "${hash_salt}"
emit AUTH_JWT_SIGNING_KEY "${jwt_key}"

# The public half of the config keypair. Not a secret - it is compiled into the
# app precisely so a device can verify a document without trusting the transport
# - but it MUST match the seed above, or every config fetch fails its signature
# and falls back to bundled defaults.
python3 - "${config_seed}" <<'PY'
import base64, hashlib, sys
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

seed = base64.b64decode(sys.argv[1])
public = Ed25519PrivateKey.from_private_bytes(seed).public_key().public_bytes(
    encoding=serialization.Encoding.Raw,
    format=serialization.PublicFormat.Raw)

print()
print("# Public - goes into the iOS bundle, not the secret store:")
print("#   ios/Sources/TankbookCore/Config/ConfigSigningKey.swift -> the RELEASE arm")
print("#   (NOT Config.default.json - that file carries config VALUES, no key)")
print(f"CONFIG_PUBLIC_KEY_BASE64={base64.b64encode(public).decode()}")
print(f"CONFIG_KEY_ID={hashlib.sha256(public).hexdigest()[:16]}")
PY
