#!/usr/bin/env bash
# Generates the two gitignored appsettings files from their committed templates.
#
# WHY THIS EXISTS: `appsettings.json` and `appsettings.Development.json` are
# gitignored (2026-09-01) so real credentials cannot reach a public repo. The
# *.template.json files beside them are committed and carry the full structure
# with the secret values blank, and this script fills them from the environment.
#
# THE MEASUREMENT THAT MADE IT NECESSARY: with `appsettings.json` absent,
# `dotnet test` ABORTS after 117 of 295 tests - the base file is load bearing
# for the suite, not just for a running server. So a fresh clone and CI must
# generate it before building, and the backend workflow does.
# `appsettings.Development.json` is NOT load bearing (295/295 without it,
# because the tests run in the "Testing" environment), but it is generated here
# too so a new checkout gets a working local dev setup in one command.
#
# Secrets are read from the environment and never written to a template:
#
#   S3_ACCESS_KEY, S3_SECRET_KEY   the Yandex static key for the
#                                  `tankbook-storage` service account
#   TANKBOOK_HASH_SALT             docs/LOGGING.md account-id hashing
#   CONFIG_SIGNING_KEY             the Ed25519 seed that signs config documents
#   AUTH_JWT_SIGNING_KEY           base64 PKCS#8 RSA access-token key
#   CATALOG_ADMIN_TOKEN, LLM_API_KEY, POSTGRES_CONNECTION
#
# Anything unset is left as the template has it - blank. That is deliberate and
# safe: `Program.cs`'s PR.34 guard refuses to start outside Development with an
# unset or placeholder secret, so a half-filled file fails loudly at boot rather
# than serving traffic with a key from this repo.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
api="${here}/../src/Tankbook.Api"

render() {
    local template="$1" output="$2"
    if [ ! -f "${template}" ]; then
        echo "error: missing template ${template}" >&2
        exit 1
    fi
    python3 - "${template}" "${output}" <<'PY'
import json, os, sys

template, output = sys.argv[1], sys.argv[2]
with open(template) as handle:
    settings = json.load(handle)

def put(path, value):
    """Set a dotted path only when the environment supplied something."""
    if not value:
        return
    node = settings
    for key in path[:-1]:
        node = node.setdefault(key, {})
    node[path[-1]] = value

put(["S3", "AccessKey"], os.environ.get("S3_ACCESS_KEY"))
put(["S3", "SecretKey"], os.environ.get("S3_SECRET_KEY"))
put(["Tankbook", "Logging", "HashSalt"], os.environ.get("TANKBOOK_HASH_SALT"))
put(["Config", "SigningKey"], os.environ.get("CONFIG_SIGNING_KEY"))
put(["Auth", "JwtSigningKeyBase64"], os.environ.get("AUTH_JWT_SIGNING_KEY"))
put(["Catalog", "AdminToken"], os.environ.get("CATALOG_ADMIN_TOKEN"))
put(["LlmGateway", "ApiKey"], os.environ.get("LLM_API_KEY"))
put(["ConnectionStrings", "Postgres"], os.environ.get("POSTGRES_CONNECTION"))

with open(output, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
PY
    echo "  wrote ${output#"${api}/"}"
}

echo "Generating appsettings from templates:"
render "${api}/appsettings.template.json" "${api}/appsettings.json"
render "${api}/appsettings.Development.template.json" "${api}/appsettings.Development.json"

# The one check that matters: a generated file that is not valid JSON fails the
# build in a way that reads as a code error, so it is caught here instead.
python3 -c "import json,sys; [json.load(open(p)) for p in sys.argv[1:]]" \
    "${api}/appsettings.json" "${api}/appsettings.Development.json"
echo "Both files are valid JSON."
