-- Tankbook backend, migration 003 (remote config).
-- docs/CONFIG.md. Signed config documents drive the "remote config" layer the
-- client resolves above its bundled defaults. The server serves the highest
-- published version whose validity window is still open; clients verify the
-- Ed25519 signature before applying anything (CONFIG.md "Guardrails on
-- apiBaseUrl", "Threat: the cache file is tampered with").

-- One row per config version. version is the monotonic document version (the
-- PK backs rollback protection: a re-published version simply cannot be
-- inserted a second time). document holds the full config document (the signed
-- content); signature is the Ed25519 signature over its canonical
-- serialization; issued_at/not_after mirror the document's own validity window
-- so the server can select without parsing the payload; published_at marks the
-- moment the document becomes eligible to be served.
CREATE TABLE config_documents (
    version      int PRIMARY KEY,
    document     jsonb NOT NULL,
    signature    text NOT NULL,
    issued_at    timestamptz NOT NULL,
    not_after    timestamptz NOT NULL,
    published_at timestamptz NOT NULL DEFAULT now()
);

-- Seed version 1: a safe baseline carrying bundled-equivalent defaults
-- (docs/CONFIG.md "What may be configured remotely"). Both capture-tier kill
-- switches are ON (no extraction is being restricted), there is no apiBaseUrl
-- override, and there is no maintenance notice. issuedAt/notAfter are generated
-- at apply time so the document stays valid for the default 90-day window after
-- deployment.
--
-- The signature is a placeholder completed by ConfigBaselineSeeder at startup:
-- an Ed25519 signature cannot be computed inside SQL, and the signing key is
-- configuration (Config:SigningKey), not schema. Until the seeder runs, the
-- row is present but not yet signed; GET /config only starts serving it once
-- signed. Clients reject unsigned documents anyway (CONFIG.md), so an
-- accidentally-unsigned baseline can never move a device.
INSERT INTO config_documents (version, document, signature, issued_at, not_after)
VALUES (
    1,
    jsonb_build_object(
        'version', 1,
        'issuedAt', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'notAfter', to_char((now() + interval '90 days') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'tier2OnDeviceLLM', true,
        'tier3CloudFallback', true,
        'llmQuota', jsonb_build_object('onDeviceLLM', 200, 'cloudFallback', 50),
        'ocrConfidenceThreshold', 0.75,
        'minSchemaVersion', 1,
        'referencePacks', jsonb_build_object('rates', 1, 'catalog', 1),
        'rolloutSalt', 'tankbook-baseline-rollout-salt'
    ),
    '',
    now(),
    now() + interval '90 days'
);
