-- Tankbook backend, migration 005 (per-device revocation).
-- docs/API.md "Account & devices": DELETE /account/devices/{id} revokes a
-- device and its next pull gets 410. The revocation marker lives on the device
-- row (not in the token) so a revoked device's still-valid bearer token cannot
-- keep reading the account stream; the sync endpoints check this column per
-- request. Revoking a device never touches records - local data stays local.

ALTER TABLE devices ADD COLUMN revoked_at timestamptz;
