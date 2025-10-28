# Asset Management Capability

## ADDED Requirements

### Asset Registry
The system shall maintain a central registry of all tradeable assets and currencies with unique identity.

#### Scenario: Asset creation during import
Given a CSV row with symbol "SPY"
When the import pipeline processes the row
Then an Asset is created if none exists with symbol "SPY"
And the Asset is cached in AssetRegistry
And subsequent references return the same Asset instance

#### Scenario: Distinct assets for different symbols
Given an import with symbols "FBTC" and "BTC"
When both are processed
Then two distinct Asset records are created
And FBTC.id ≠ BTC.id
And each maintains its own price and metadata

### Asset Classification
Assets shall be classified by type with special handling for cash equivalents.

#### Scenario: Money market fund classification
Given an Asset with symbol "SPAXX"
When setting its properties
Then isCashEquivalent can be set to true
And it appears in cash calculations
And portfolio views treat it as cash-like

#### Scenario: Asset class categorization
Given an Asset "VOO"
When classified
Then assetClass is set to .etf
And it groups with other ETFs in portfolio views
And analytics can filter by class

### Institution-Specific Symbol Resolution
The system shall resolve institution-specific symbols to canonical assets.

#### Scenario: Institution symbol mapping
Given Fidelity uses "FXAIX" for their S&P 500 fund
When importing from Fidelity with symbol "FXAIX"
Then AssetRegistry.resolveSymbol("FXAIX", institution: "fidelity") returns the FXAIX Asset
And the asset is distinct from "SPY"
And both track in separate positions

## MODIFIED Requirements

### JournalEntry Asset Linking
Journal entries shall link to Asset objects instead of string symbols.

#### Scenario: Asset relationship in journal entries
Given a JournalEntry for buying SPY
When created through the import pipeline
Then journalEntry.asset points to the SPY Asset object
And journalEntry.accountName maintains "SPY" for compatibility
And the relationship is bidirectional

## REMOVED Requirements

### Automatic Symbol Aliasing
The system shall NOT automatically alias similar symbols.

#### Scenario: No automatic aliasing
Given symbols "GBTC" and "BTC"
When both are imported
Then they remain distinct assets
And no automatic aliasing occurs
And user must explicitly manage each