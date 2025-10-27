# Project Context

## Purpose
A local-first, CloudKit-synced macOS/iPadOS financial intelligence platform that:
- Aggregates financial data from any source (CSV, JSON, PDF exports)
- Normalizes transactions into a canonical append-only ledger
- Provides real-time portfolio analysis, cash flow tracking, and budget intelligence
- Maintains complete privacy with all computation happening on-device
- Enables reactive time streams for live financial insights

## Tech Stack
- **Platform**: macOS/iPadOS (universal binary)
- **UI Framework**: SwiftUI + Catalyst
- **Reactive Framework**: Combine
- **Data Layer**: SwiftData + SQLite (WAL mode)
- **Persistence**: Core Data + CloudKit (encrypted sync)
- **Language**: Swift 6.0
- **Build System**: Xcode 16+ / Swift Package Manager
- **CLI**: Swift ArgumentParser for command-line interface
- **Data Processing**: Swift Numerics, Charts framework
- **Export Formats**: CSV, JSON, TradingView Pine Script

## Project Conventions

### Code Style
- **Swift Style**: Follow Swift.org API Design Guidelines
- **Naming**:
  - Types: UpperCamelCase (e.g., `LedgerEntry`, `ParserTemplate`)
  - Variables/Functions: lowerCamelCase (e.g., `calculateNetWorth`)
  - Constants: same as variables, not all caps
- **File Organization**: One type per file, matching the type name
- **Access Control**: Prefer `private` by default, expose only what's needed
- **Optionals**: Use guard statements for early exits, avoid force unwrapping
- **Error Handling**: Use Swift's Result type and async/await patterns
- **Comments**: Document why, not what; use `///` for public APIs

### Architecture Patterns
- **Reactive DAG Architecture**: All data flows through a directed acyclic graph
  - Event-sourced updates (append-only)
  - Dependency tracking for automatic recomputation
  - Incremental updates for changed subsets
- **MVVM Pattern**: SwiftUI views backed by ObservableObject view models
- **Repository Pattern**: Data access through protocol-based repositories
- **Parser Strategy Pattern**: Pluggable parsers for different file formats
- **Domain-Driven Design**: Clear separation between domain models and infrastructure
- **Coordinator Pattern**: Navigation logic separated from views
- **Local-First Design**: All operations work offline, sync is optional

### Testing Strategy
- **Unit Tests**: Test domain logic, parsers, and calculations in isolation
- **Integration Tests**: Test data flow through the reactive DAG
- **UI Tests**: XCTest for critical user workflows (import, parse, export)
- **Property-Based Testing**: Use SwiftCheck for financial calculations
- **Test Coverage**: Aim for 80% coverage on business logic
- **Test Naming**: `test_functionName_givenCondition_expectedResult()`
- **Test Data**: Use fixtures in `Tests/Fixtures/` for sample financial data
- **Performance Tests**: Measure import and calculation performance

### Git Workflow
- **Branching Strategy**: Feature branches off main
  - Branch naming: `feature/`, `fix/`, `refactor/` prefixes
  - Short-lived branches (merge within 3 days)
- **Commit Convention**: Conventional commits format
  - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
  - Format: `type: description` (under 50 chars)
  - Example: `feat: add CSV parser for bank statements`
- **PR Process**: All changes via pull request with CI checks
- **Release Strategy**: Semantic versioning (major.minor.patch)

## Domain Context
### Financial Concepts
- **Ledger Entry**: Canonical transaction record with double-entry bookkeeping
- **Position**: Holdings of a specific asset at a point in time
- **Valuation**: Position value calculated with latest price and FX rates
- **Allocation**: Portfolio distribution across asset classes
- **Cash Flow**: Income minus expenses over time periods
- **Parser Template**: Mapping rules from source format to canonical schema

### Data Sources
- **Bank Exports**: CSV/PDF statements with transactions
- **Brokerage Reports**: Trading activity, positions, dividends
- **Crypto Wallets**: Blockchain transaction exports
- **Superannuation**: Australian retirement account statements
- **Credit Cards**: Monthly statements in various formats

### Reactive Streams
- **Price Series**: Continuous market data for assets
- **FX Series**: Currency conversion rates over time
- **Position Stream**: Real-time holdings calculations
- **Valuation Stream**: Live portfolio value updates
- **Budget Stream**: Rolling income/expense tracking

## Important Constraints
- **Privacy-First**: No data leaves device except encrypted CloudKit sync
- **Apple-Only**: macOS 14+ and iPadOS 17+ requirement
- **Performance**: Must handle 100K+ transactions with sub-second updates
- **Storage**: SQLite with WAL mode for ACID compliance
- **Memory**: Incremental processing for large imports (streaming)
- **Accuracy**: Financial calculations must be precise to 4 decimal places
- **Compliance**: No financial advice, display-only intelligence
- **Offline-First**: Full functionality without network connection

## External Dependencies
### Apple Frameworks
- **CloudKit**: Encrypted sync across devices
- **StoreKit**: Future premium features
- **CryptoKit**: Local data encryption

### Third-Party Services (Optional)
- **Market Data**: Yahoo Finance API fallback for prices
- **FX Rates**: ECB or RBA feeds for currency conversion
- **PDF Parsing**: On-device OCR via Vision framework

### Data Formats
- **Import**: CSV, JSON, PDF, QIF, OFX
- **Export**: CSV, JSON, TradingView Pine Script
- **Internal**: SQLite, Core Data, JSON serialization
