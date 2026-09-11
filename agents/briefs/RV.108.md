# RV.108 - `GET /v1/account` is normative in API.md and does not exist

**Scenario: J11a · first sign-in.** The only v1 row holding J11a open. **A decision in one
direction**, then the work that direction implies.

`docs/API.md:536` documents `GET /account` -> `{ accountId, email, createdAt, storage: {usedBytes,
quota}, llm: {used, quota, period} }`. `Program.cs:598-603` maps `/devices`, the push-token put,
device delete and account delete - **no bare `MapGet`**, and no test references it.

## Decide

**Check the client first.** If the iOS Settings / Account & devices screen renders storage or
quota figures, find where they come from today; if from nowhere, the endpoint is wanted and this
row implements it (backend: route, handler, tests per `docs/TESTING.md`'s endpoint matrix; client:
the read). If nothing consumes it, **delete the row from `API.md`** and say so - a contract with
neither a route nor a test is a promise a client would 404 on. **One direction. Say which.**

## Tests

If implemented: backend endpoint tests (auth required, shape, quota values derived not stored -
hard rule 2's spirit); client L1 decoding the documented shape. If deleted: the `API.md` diff and a
grep proving no client reference.

## Mutation - named

If implemented: remove the route; the endpoint test 404s. If deleted: none - a doc change; say so.
