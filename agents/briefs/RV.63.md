# RV.63 – one log field, `accountHash`, carries two values that cannot be compared

Found 2026-09-04 while diagnosing RV.58. **The cost is demonstrated, not hypothetical**: reading a
production log, the orchestrator concluded a device had pushed a user's fill-up into the WRONG
ACCOUNT and filed it as a serious defect. It was two hashes of one account. An operator would have
made the same error, with less time to check it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`backend/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `ios/` file.

**A sibling agent (RV.61) is working in `ios/`** – ignore it, and do not run iOS tooling.
**Never move, rename or delete a file you did not create.** There is a git worktree at
`.claude/worktrees/rv48` belonging to another session; it is not yours.

## The diagnosis, verified – confirm it, do not re-derive it

`backend/src/Tankbook.Api/Logging/AccountHash.cs` has two entry points:

- `Compute(email, salt)` – hashes the **email**;
- `ForAccount(accountId, salt)` – which is `Compute(accountId.ToString("N"), salt)` underneath, so
  it hashes the **account id**.

**Both render as `acct_xxxxxxxx` under the same log key.** Emitters:

- EMAIL hash: `Auth/AuthService.cs:121`, `Account/AccountService.cs:98`,
  `Account/AccountPurgeService.cs:86`
- ACCOUNT-ID hash: `Logging/LogScopeEnrichmentMiddleware.cs:79` – i.e. **every bearer request**

So one account logs under two different identifiers and two lines about the same user **do not
join**. `docs/LOGGING.md` says the field exists to correlate a support request; it cannot do that
when its value depends on which code path logged it.

The real production evidence: `auth.session` logged `accountHash=acct_64875a77` while the same
device's `sync.push` on the same second logged `accountHash=acct_c876a1fa`.

**`ForAccount`'s own doc comment already explains WHY the second form exists** – a bearer token
carries the account id, not the email, so a bearer request cannot recompute the email hash. That
reasoning is sound. **The defect is that both then answer to the same name.**

## What to build

**One identifier per account, or two field NAMES.** Two defensible shapes:

1. **Preferred: make everything log the ACCOUNT-ID hash.** `auth.session` resolves the account on a
   matched sign-in, so the account id is available at the point it logs. One identifier is what
   makes a log joinable, and the account id is the one that survives an email change.
2. Emit the email hash under a **distinct key** (`emailHash`) so the two can never be mistaken.

**Pick one and say why.** If you choose (1), check the sign-in paths where the account does NOT yet
exist or is not yet resolved (a first-time registration, a rejected refresh) and say what those log
– a null is honest, a silently-different-shaped hash is not.

**Hard rule 12 is not at issue** – both values are salted hashes, neither is a domain value. This is
a clarity and correctness fix, not a privacy one. Do not "fix" it by removing the field.

**Fix `docs/LOGGING.md` in the same change** – it is the authority for what each field means, and it
currently describes one field where there are two.

## Read before writing

1. **`CLAUDE.md`** – hard rule 12 (what is loggable), rule 14.
2. `docs/LOGGING.md` §1 and §2 – §2 is where the per-request stand-in is described.
3. `backend/src/Tankbook.Api/Logging/AccountHash.cs`, `LogScopeEnrichmentMiddleware.cs`,
   `Auth/AuthService.cs`, `Account/AccountService.cs`, `Account/AccountPurgeService.cs`,
   `Logging/TankbookRedactor.cs` (it calls `Compute` too – decide what that one should do and say so).

## Tests

**Backend 384 today; must not fall.**

- **The headline L2: two log lines about ONE account – one from `auth.session`, one from an
  authenticated request – carry the SAME `accountHash`.** Assert the two VALUES are equal. That is
  the whole point, and it fails today.
- L1: the two hash entry points cannot both feed the same log key – a test-level guard so this
  cannot regress quietly.
- If you keep a second key, assert its NAME differs and that both appear where expected.

**Vacuous-assertion traps, named:**
- Asserting `accountHash` is non-empty, or matches `acct_[0-9a-f]{8}`. Both were true throughout the
  bug – the shape was never wrong, the VALUE was inconsistent.
- Asserting one line in isolation. The defect only appears when two lines are COMPARED.

**Mutation-check and report it**: restore the email-hash call at the `auth.session` site and confirm
the equality test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd backend && dotnet build ; echo "BUILD=$?"
    cd backend && dotnet format --verify-no-changes ; echo "FORMAT=$?"
    cd backend && dotnet test ; echo "TEST=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
`backend/scripts/dev-up.sh` starts Postgres + MinIO (plain `docker run`, no compose).
Match the process NAME (`pgrep -x ...`); **never `pgrep -f`**.

## Screenshots

None applies – backend logging only. Say so rather than fabricating one.

## Report back

- Exit codes (captured, not piped), test counts before/after, the mutation result.
- **Which shape you chose** (one identifier, or two names) and why.
- **What the unresolved-account sign-in paths now log**, named explicitly.
- What you decided for `TankbookRedactor`'s `Compute` call.
- What you changed in `docs/LOGGING.md`.
- Anything you noticed that is not RV.63 – named separately.
