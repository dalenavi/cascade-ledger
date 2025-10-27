# Project Overview: Financial Intelligence Platform (Mac/iPad)

## Purpose

A local-first, CloudKit-synced macOS/iPadOS app that aggregates
financial data from any source, normalizes it into a canonical ledger,
and provides real-time portfolio, cash flow, and budget intelligence.

------------------------------------------------------------------------

## Core Principles

-   **Local-first privacy**: all computation happens on-device; CloudKit
    used only for encrypted sync.\
-   **Reactive time streams**: live updates from any data change, not
    static daily snapshots.\
-   **Append-only ledger**: immutable record of every financial event.\
-   **User-assisted parsing**: collaborative interface to map raw
    exports to canonical structure.\
-   **Versioned DAG lineage**: each derived dataset is traceable,
    versioned, and recomputed reactively.\
-   **Unified intelligence**: investment, budget, income, expenses ---
    all one model.\
-   **CLI-first orchestration**: agents and automation use the same
    reactive core as the UI.

------------------------------------------------------------------------

## Core Entities

  -------------------------------------------------------------------------
  Category                Entity                Description
  ----------------------- --------------------- ---------------------------
  Input                   **RawFile**           Uploaded financial export
                                                (CSV, JSON, PDF). Stored
                                                verbatim.

  Input                   **ImportBatch**       A single user upload with
                                                date range & parser
                                                template.

  Parsing                 **ParserTemplate**    Mapping rules from source
                                                columns → canonical fields.
                                                Versioned and reusable.

  Ledger                  **LedgerEntry**       Canonical transaction
                                                record; append-only, typed,
                                                tagged, FX-aware.

  Accounts                **Account**           Tracks source institution
                                                and type (brokerage, super,
                                                wallet, cash).

  Assets                  **Asset**             Canonical definition of an
                                                instrument (stock, crypto,
                                                fund, cash).

  Streams                 **PriceSeries**,      Continuous market data and
                          **FXSeries**          currency conversion
                                                streams.

  Derived                 **PositionStream**,   Reactive computed streams
                          **ValuationStream**   of holdings and value.

  Intelligence            **Budget**,           Higher-level insights from
                          **Allocation**,       the reactive DAG.
                          **CashFlow**,         
                          **Analytics**         
  -------------------------------------------------------------------------

------------------------------------------------------------------------

## Data Flow (Reactive DAG)

    RawFile → ParserTemplate → LedgerEntry → PositionStream → ValuationStream → Analytics
            ↘ FXSeries, PriceSeries → (join for valuation)

-   All nodes are **versioned** and record provenance.
-   Updates flow **reactively** downstream.
-   Staleness is visible (each node knows `last_updated` &
    dependencies).

------------------------------------------------------------------------

## Intelligence Layers

  -----------------------------------------------------------------------
  Layer                 Output                      Notes
  --------------------- --------------------------- ---------------------
  Allocation            Target vs actual mix; drift Reactive by price or
  Intelligence          alerts.                     trade.

  Budget Intelligence   Income, expense, savings,   Unified ledger
                        net rate.                   categories.

  Transaction           Categorization, tagging,    Rule + ML hybrid.
  Intelligence          anomaly detection.          

  Cash Flow             Real-time inflows/outflows, Derived from tagged
                        rolling savings.            ledger.

  Parser Intelligence   Learns from user            Interactive feedback
                        corrections; adapts         loop.
                        mappings.                   
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## Interfaces

### CLI (canonical control plane)

Commands: - `fin upload`, `fin parse`, `fin commit` -
`fin snapshot --live` - `fin chart`, `fin export tradingview` -
`fin reconcile`, `fin rules apply`

### Human UI (SwiftUI)

-   Dashboard: live portfolio & cash flow charts.\
-   Import Studio: file upload + parser collaboration.\
-   Ledger Browser: tag, correct, and filter.\
-   Rule Studio: auto-categorization logic.\
-   Reports: allocation drift, budget vs actual, IRR.

------------------------------------------------------------------------

## Reactive Architecture

  -----------------------------------------------------------------------
  Concern                     Best Practice
  --------------------------- -------------------------------------------
  **Event model**             All updates are event-sourced; append-only
                              logs.

  **Propagation**             DAG-based dependency tracking; dirty-node
                              recomputation.

  **Incrementality**          Incremental recompute for changed subsets
                              only.

  **Temporal joins**          "latest-before" joins for price and FX
                              streams.

  **Concurrency**             Combine-based publishers, debounced
                              propagation.

  **State store**             SQLite (WAL) for durable, reactive
                              persistence.
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## Technical Stack

-   **Frontend**: SwiftUI + Combine + Catalyst (Mac/iPad).\
-   **Local DB**: SQLite + GRDB.\
-   **Reactive Engine**: Combine DAG orchestrator.\
-   **Sync**: CloudKit (encrypted).\
-   **Compute**: Local worker queue (reactive propagation).\
-   **Exports**: CSV, TradingView, accounting formats.

------------------------------------------------------------------------

## Roadmap (Phased Delivery)

1.  **MVP** --- Ledger ingestion, parser collaboration, reactive
    charts.\
2.  **Phase 2** --- Rule engine, FX/price streams, allocation & budget.\
3.  **Phase 3** --- CloudKit sync, TradingView export, multi-interface
    (CLI, UI, agent).

------------------------------------------------------------------------

## Guiding Philosophy

> The app is a **living ledger** --- reactive, verifiable, and private
> --- unifying income, spending, and investment intelligence for the
> modern human.
