-- Tankbook backend, migration 008 (silent sync-nudge throttle).
-- docs/NOTIFICATIONS.md "Scenario catalog" pins the sync nudge as "throttled
-- server-side (max ~1/15 min per device)". The throttle needs one piece of state
-- not present in 001: when a device was last nudged. Null means "never nudged",
-- so a fresh install is immediately eligible and the column needs no default.
-- The nudge claim is a conditional UPDATE keyed by the device primary key, so no
-- extra index is required.

ALTER TABLE devices ADD COLUMN last_nudged_at timestamptz;
