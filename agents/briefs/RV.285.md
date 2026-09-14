# RV.285 - the gateway's provider call has no bounded timeout: `/extract` held for 102 s, then 502

**Scenarios: F4 · cloud LLM fallback unavailable (the wait has a budget), J3 · the receipt.**
Found 2026-09-14 in the production log: two `llm.extract` calls at 18:37 and 18:38 ended
`provider_failed` after **102 565 ms** and **102 951 ms**, each returned to the device as a 502
after 105 s, with `Model=` empty. The provider was down that afternoon (the same outage killed
four agent dispatches at the banner); the point is not that it failed but that the server waited
**100 s** to find out - the .NET `HttpClient` default - and held a request thread, the device's
background task and the user's quota unit for that long.

## The cause, pinned

- `OpenAiCompatibleLlmProvider` takes `httpClientFactory.CreateClient()` - the **bare** client
  (`backend/src/Tankbook.Api/Llm/OpenAiCompatibleLlmProvider.cs:32-34`), registered with no
  timeout at `Program.cs:226`, whose own comment says "the bare default client remains for the
  LLM gateway (its own vendor contract, v2)". The named clients beside it carry budgets
  (`HttpClientTimeouts.Jwks` 15 s, `RateFeed` 30 s, `Apns` 30 s;
  `backend/src/Tankbook.Api/Http/HttpClientTimeouts.cs`).
- `LlmService.ExtractAsync` catches everything as `provider_failed` (`LlmService.cs:195-198`); a
  timeout is indistinguishable from a 5xx in the ledger and the log.
- The measured healthy answer is 12-36 s (`RV.51`), the one successful call today took 21.5 s;
  the device stops waiting at 3 s (`API.md` rule 2) and takes a late answer through the inbox, so
  the server's budget bounds the **work**, never the user.

**This brief's diagnosis is a hypothesis - confirm on the tree before you change anything.**

## Build

1. `HttpClientTimeouts.Llm` - a compiled constant (`docs/PRACTICES.md` constants policy: compiled,
   with the reason in the doc comment): **60 s**, twice the slowest measured healthy answer and
   short enough that a dead provider releases the request in a minute, not two. A named client
   `"llm"` in `Program.cs`; the provider takes it by name. Keep the `Program.cs` comment honest.
2. `LlmService`: a `TaskCanceledException` from the client's timeout is recorded as
   `provider_timeout` (a new outcome constant, ledger + log), never `provider_failed`; the ledger
   row still lands (the call was attempted, the cost is zero tokens - say so in the row).
3. `docs/API.md` "The device's side of /extract" gains the server side: the provider budget, the
   outcome name, and that a 502 after the budget is the same F4 path on the device.
   `docs/LOGGING.md` outcome vocabulary; `docs/ERRORS.md` if the device's F4 card text names it.

Out of scope: retrying the provider (a second 60 s on a dead provider is worse); the device's 3 s
budget.

## Tests

- **Backend, fails today**: `ExtractEndpointTests` (or a `RecordingLlmProvider` variant) with a
  provider that never answers: the call ends within the budget with `provider_timeout`, the ledger
  row carries that outcome, and the HTTP response is the 502 the device already handles. Uses a
  fake clock or a short injected timeout - never a real 60 s wait in the suite.
- `HttpClientTimeoutTests` (exists) gains the `llm` client.

## Mutation - named

Register the `llm` client without the timeout; the never-answering-provider test goes red (or
hangs to the test's own deadline - report which). Verbatim, then restore.

## Vacuous trap

Setting the timeout and letting the exception still land as `provider_failed`, so the log cannot
tell an outage from a slow provider - which is the question this row was filed to answer.
