# Subscription usage at equivalent API prices

Researched 2026-09-18. Read-only inspection of current upstream `NousResearch/hermes-agent` main, verified using `git ls-remote` and a fresh temporary clone: **`a566d20d226a8e2ef0747639dc8a3fc1c43f9dba`**, committed 2026-09-17. No application/backend changes. Wing targets unmodified upstream Hermes; the existing local backend checkout was not used as the target.

## Conclusion

A client-side **“API-equivalent estimate”** is feasible. Hermes already records uncached input, cache reads, cache writes, and output independently, but deliberately reports subscription usage as included at zero cost. Neither the inspected accounting API nor Desktop provides a switch to reprice subscription usage at public API rates. Wing can apply its own versioned rate table to existing usage data without changing Hermes. The current model analytics endpoint supports a useful partial estimate, not exact retrospective billing: it omits cache writes and request-level context tiers.

## Upstream accounting and API

- `openai-codex` resolves to `subscription_included`. The pricing lookup returns an all-zero included entry, and `estimate_usage_cost` short-circuits to `amount_usd=0`, `status="included"`, `label="included"`. This is intentional subscription treatment, not a missing price lookup. The same module contains actual API prices for `gpt-6-astra`, including cache writes and the 272,000-token threshold, but Codex never reaches those prices. Correction on reinspection: this revision also bundles `gpt-5.6-sol` pricing, but its July snapshot ($5 input / $0.50 cache read / $30 output per million) differs from the official rates verified below. [Sol snapshot](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/agent/usage_pricing.py#L156-L163). [Billing route and pricing implementation](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/agent/usage_pricing.py#L245-L257), [included route](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/agent/usage_pricing.py#L552-L603).
- **Canonical `input_tokens` is already uncached.** Responses/Chat total input has cached reads and writes subtracted during normalization. `prompt_tokens` is the sum of these three input buckets; output includes reasoning, so reasoning must not be charged twice. The canonical counters are persisted unchanged. [Normalization](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/agent/usage_pricing.py#L493-L545), [persistence](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/agent/turn_usage.py#L252-L274).
- `GET /api/analytics/models?days=…&profile=…` supplies model/provider, uncached input, output, cache reads, reasoning, stored estimated/actual cost, sessions and calls. It **does not supply cache-write counts, cost status, billing mode, rates, or request-level usage**. Its time window selects sessions by start time, rather than individual calls. Primary usage is grouped by the session's model/provider; auxiliary model/task rows are appended. Repricing inherits these aggregation limitations, including sessions that switched models. [Actual endpoint query/response](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/hermes_cli/web_routers/analytics.py#L221-L313).
- Unknown estimates are `None`/`unknown` internally; the analytics endpoint uses `COALESCE(SUM(...), 0)` and drops status. Therefore a zero analytics value does not by itself distinguish unknown pricing from included usage. [Unknown cost behavior](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/agent/usage_pricing.py#L548-L589), [analytics query](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/hermes_cli/web_routers/analytics.py#L238-L257).
- `GET /api/sessions/{id}` returns the session row, so session-level cache writes and billing status can be read through a stock endpoint. This still does not reconstruct per-request context tiers or correct model attribution after a switch. Codex app-server runtime itself records cache writes as zero because its protocol exposes none. [Session detail](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/hermes_cli/web_routers/sessions.py#L479-L492), [raw session selection](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/hermes_state_sessions.py#L756-L768), [Codex runtime](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/agent/codex_runtime.py#L88-L118).
- `/api/model/options` can expose picker pricing for supported live catalogs. Its provider pricing helper supports OpenRouter, Nous, AI Gateway, Novita, DeepInfra and Fireworks, returning an empty map otherwise. It is not an OpenAI/Codex API-equivalent rate endpoint. [Provider pricing contract](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/hermes_cli/models_pricing.py#L484-L497).

## Hermes Desktop

The inspected Desktop Command Center loads `/api/analytics/usage`. Its Usage panel renders sessions, calls, input/output totals, daily token bars, top models and skills; it does not recalculate subscription dollar values. Sidebar costs derive from stored actual/estimated costs and omit values below one cent. No API-equivalent pricing control was found in these paths. [Desktop Usage panel](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/apps/desktop/src/app/command-center/index.tsx#L552-L677), [sidebar cost source](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/apps/desktop/src/store/sidebar-archive.ts#L35-L36), [sidebar visibility](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/apps/desktop/src/app/chat/sidebar/chrome.tsx#L270-L274).

## Current Wing screen

The screenshot is `AdminUsagePage` in [admin_health_page.dart](../../lib/core/screens/administration/admin_health_page.dart), not the older `ProfileUsagePanel`. It calls `analytics/models` (lines 419–420), sums finite nonnegative `estimated_cost` (434–442), displays “Hermes estimates, not provider invoices” (479), and currently expands only sessions/calls/input/output/cost (549–555). Raw response maps retain other fields, so using `cache_read_tokens` needs no transport change. These local references were inspected by the main agent.

## Published OpenAI rates and client design

Official model pages checked by the main agent on 2026-09-18. Standard USD per million tokens:

| Model | Uncached input | Cache read | Cache write | Output |
| --- | ---: | ---: | ---: | ---: |
| `gpt-6-astra` | $10 | $1 | $12.50 | $50 |
| `gpt-5.6-sol` | $4 | $0.40 | $5 | $20 |

Sources: [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra), [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol). Sol cache write is derived from the documented 1.25× input rate. Astra prompts above 272k use 2× input/cache rates and 1.5× output; Sol documents 2× input and 1.5× output above 272k, with less explicit cache-tier wording. Aggregate totals cannot reveal which requests crossed the threshold.

With complete canonical buckets:

```text
API-equivalent USD =
  (uncached_input × input_rate
   + cache_reads × cache_read_rate
   + cache_writes × cache_write_rate
   + output × output_rate) / 1,000,000
```

Recommended initial scope: calculate the available uncached/read/output components locally, clearly identify the result as an **API-equivalent base-rate estimate**, and disclose that cache writes and long-context adjustments are unavailable in this aggregate view. Missing cache writes must not silently mean zero. Keep the server's subscription-included value distinct from the hypothetical estimate. Use exact model IDs with versioned prices and source/date metadata; unknown models should show unavailable and partial totals should identify incomplete coverage. Do not guess another model's rates or treat unknown rates as free. More complete session-level calculations are possible with additional stock reads but remain approximate for mixed-model histories and unavailable per-request tiers.

## Follow-up: scope of subscription repricing

Rechecked upstream main at `d177b119e9c56c9ddc0b7379ffce52341ec06584`. The central billing resolver has a provider-wide rule for `openai-codex`, independent of model ID; it does not enumerate zero-priced subscription models. This is the only explicit `subscription_included` provider branch in that resolver. Wing can therefore scope its local rate catalogue to models used through that provider, while continuing to display Hermes estimates for other routes. A numeric zero alone must not trigger repricing. [Resolver](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/agent/usage_pricing.py#L326-L363).
