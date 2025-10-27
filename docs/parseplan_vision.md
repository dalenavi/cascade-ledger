
# ParsePlan: Vision & High‑Level Architecture

A concise blueprint for **Parser Studio’s** transformation core. This document communicates intent, core abstractions, integration points, examples, and gotchas so we can implement specs elsewhere with confidence.

---

## Why ParsePlan
We need a deterministic, versioned way to turn **arbitrary exports** (CSV/TSV/XLSX/JSON/PDF→tables/logs) into a **canonical ledger** while staying **interactive**, **reactive**, and **auditable**.

**Goals**
- **Deterministic** parsing with human‑readable plans (diffable, testable, replayable).
- **Interactive** authoring with live preview and incremental recompute.
- **LLM‑assisted**, never LLM‑executed: Claude proposes, the engine validates and runs.
- **Composable** with existing open standards to avoid inventing a monoculture.
- **Versioned lineage**: every output is traceable to source rows, plan version, and engine build.
- **Local‑first**: on‑device parse; CloudKit sync for plans, states, and artifacts.

---

## Design Tenets
1. **Event‑sourced core**: imports and edits become immutable events; derived views are projections.  
2. **Reactive DAG**: updates propagate downstream (raw→normalized→positions→valuation).  
3. **Thin glue on standards**: prefer Frictionless/CSVW (dialects/schemas), JSONata/JOLT (transforms), Great Expectations (validation), Singer/Airbyte (source/state), OpenLineage (lineage).  
4. **Guardrails over guesswork**: LLM produces *deltas* in supported specs; engine dry‑runs before commit.  
5. **Human in the loop**: Studio shows errors, lineage, and suggestions; user decides.

---

## Core Objects (IR level)
- **RawFile**: immutable uploaded artifact (with checksum, source_hint).  
- **ImportBatch**: one ingestion act; binds RawFile + plan version + time window.  
- **ParsePlan**: declarative recipe (dialect, schema map, transforms, validation, lineage hints).  
- **ParseRun**: execution of a plan against a batch; produces rows + warnings + errors + lineage map.  
- **LedgerEntry**: canonical normalized transaction rows (append‑only).

---

## ParsePlan (conceptual shape)
ParsePlan isn’t a brand‑new DSL; it’s a **container** that wires established pieces:

- `dialect:` **Frictionless Table Dialect** / CSVW dialect (delimiter, quote, encoding, header rows).  
- `schema:` **Frictionless Table Schema** / CSVW tableSchema (types, constraints, missing values).  
- `transform:` sequence of steps expressed as **JSONata** or **JOLT** (one per step).  
- `validate:` **Great Expectations**‑style checks (e.g., date parse, ranges, uniqueness).  
- `source:` optional **Singer/Airbyte** connector config/state for incremental imports.  
- `lineage:` **OpenLineage** metadata (run, inputs/outputs, column facets).

### Minimal example (YAML)
```yaml
version: 1
dialect:
  delimiter: ","
  header: true
  encoding: utf-8
schema:
  fields:
    - name: date        type: date     format: "%Y-%m-%d"
    - name: account_id  type: string
    - name: asset_id    type: string
    - name: type        type: string   constraints: {enum: ["BUY","SELL","DIVIDEND","FEE"]}
    - name: qty         type: number
    - name: unit_price  type: number
    - name: amount      type: number
    - name: fee         type: number   missingValues: ["", null]
    - name: currency    type: string   default: "USD"
transform:
  - kind: jsonata
    expr: >
      $.map(function($r){
        $merge([$r, {
          amount: $number($r.Quantity) * $number($r.Price),
          type: (
            $contains($uppercase($r.Description),"DIV") ? "DIVIDEND" :
            ($number($r.Quantity) > 0 ? "BUY" :
            ($number($r.Quantity) < 0 ? "SELL" : "FEE"))
          )
        }])
      })
  - kind: jolt
    spec:
      - operation: shift
        spec:
          "*":
            "Trade Date": "[&1].date"
            "Account":    "[&1].account_id"
            "Ticker|Symbol|Security": "[&1].asset_id"
            "Quantity":   "[&1].qty"
            "Price":      "[&1].unit_price"
            "Fee":        "[&1].fee"
validate:
  expectations:
    - expect_column_values_to_not_be_null: { column: date }
    - expect_column_values_to_be_between: { column: qty, min_value: -1000000, max_value: 1000000 }
    - expect_column_values_to_match_regex: { column: currency, regex: "^[A-Z]{3}$" }
lineage:
  owner: "user:123"
  labels: ["fidelity","activity"]
```

---

## Authoring Experience (Parser Studio)
- **Profile**: auto‑detect dialect, header issues, datatypes; show sample.  
- **Propose**: Claude Agent suggests a starting plan from headers + 50 rows + ontology.  
- **Preview**: live re‑run on sample after each edit; incremental evaluation.  
- **Explain**: hover any output cell to highlight source cells (lineage).  
- **Repair**: when errors cluster (e.g., date fails), Claude proposes a delta; user accepts.  
- **Commit**: full parse runs with chunking; ledger entries append; lineage & validation report stored.

### Editor affordances
- Quick actions: split/trim/clean currency, coalesce columns, enum map, sign‑fix for SELL rows.  
- Rule Studio: author JSONata/JOLT snippets with type‑aware autocomplete.  
- Drift detector: detects column or format changes since the last plan; opens Fix Mode.

---

## Live Reactivity (beyond daily snapshots)
- **Transactions** stream updates → **Positions** recompute → **Valuation & Allocations** animate in UI.  
- Price/FX updates also trigger downstream updates.  
- Each node carries `last_updated`, `version`, `derived_from` and a **dirty flag**; recompute is debounced and incremental.

---

## Integration: Claude Agent SDK
**Roles**
- `SuggestMapping`: generate first plan from headers + ontology.  
- `FixErrors`: propose plan deltas for parse failures.  
- `Categorize`: map descriptions to ledger types/tags.  
- `ValidateSemantics`: draw attention to likely field swaps, inverted signs, odd fees.

**Guardrails**
- Agent outputs **only**: JSONata/JOLT fragments, Frictionless/CSVW schema deltas, GE expectations.  
- Engine performs static checks + dry‑run on sample before applying.  
- All agent actions are logged and reversible; humans approve every change.

---

## Testability & Quality
- **Golden tests**: each plan bundles fixtures → expected ledger rows.  
- **Static checks**: required fields present, enums valid, FK to accounts/assets resolvable.  
- **Statistical checks**: z‑scores for outliers; duplicate tx detection; balance sanity.  
- **Drift alerts**: plan invalidation when source stats/headers shift.

---

## Performance & Safety
- **Incremental evaluation** for live preview (cached columnar sample).  
- **Vectorized full runs** using Arrow/Parquet in memory; CSV streamed in chunks.  
- **Sandbox transformlets** (optional escape hatch) run in WASM/JS with CPU/time quotas, no file/net.  
- **Memory discipline**: spill large intermediates; backpressure on UI; resumable runs.

---

## Interop & Exports
- **Singer/Airbyte** source configs supported as inputs.  
- **TradingView** export of normalized transactions or valuation series.  
- **Accounting** exports (CSV/ledger) and **OpenLineage** events for external catalogs.

---

## Things to Watch For (Gotchas)
- **Ambiguous headers**: multiple columns map to the same semantic field; require coalesce order.  
- **Signs & fees**: SELL quantities and negative fees show up inverted in some brokers; add normalization rules.  
- **Currency formatting**: locale‑specific thousands/decimal separators; strip symbols before parse.  
- **Corporate actions**: splits, spin‑offs, dividends; model as explicit events, not guesses.  
- **Transfers**: internal money/asset moves should net to zero in consolidated ledger; pair legs with `transfer_ref`.  
- **Late data**: support event‑time vs processing‑time; allow replay and retroactive recompute.  
- **PDF statements**: table detection misreads; fall back to grok/dissect rules or manual table ranges.  
- **Plan drift**: source export version changes silently; maintain heuristics + alerts.  
- **LLM hallucination**: never execute free‑form suggestions; compile to known specs and validate first.

---

## Minimal CLI (same engine)
```
fin upload bank.csv
fin template suggest --file bank.csv > plan.yaml
fin parse --file bank.csv --plan plan.yaml --dry-run
fin commit --batch 2025-10-26-b1
fin export tradingview --from 2025-01-01 --to 2025-12-31
```

---

## Non‑Goals
- Building a full ETL platform; we’re focused on **ingest→normalize→analyze** for personal finance.  
- Making LLM the executor; it remains proposer/assistant only.

---

## North Star
> **ParsePlan turns messy exports into a living, versioned ledger — safely, interactively, and fast — so allocation, budget, and cash‑flow intelligence are always correct and current.**
