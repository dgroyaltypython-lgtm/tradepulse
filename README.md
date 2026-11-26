# TradePulse OI — Android Trading Journal

A Flutter Android app starter for recording trades, importing an NSE-style option-chain CSV, classifying CE/PE premium + OI changes, exporting reports, and preparing WhatsApp trading setups.

## Features in this build

- Premium Material 3 interface with dashboard, OI Analyzer, Trading Journal, and Reports.
- Imports the supplied NSE-style CSV layout: first row CALLS / PUTS group headings, second row field headings, then option rows.
- Reads strike, CE/PE LTP, premium change, OI, change in OI, volume, and IV. Handles comma-separated Indian numbers and `-` blanks.
- Classifies each CE and PE contract using premium change and change in OI:
  - Premium up + OI up: Fresh Long Build-up
  - Premium down + OI up: Short Build-up
  - Premium up + OI down: Short Covering
  - Premium down + OI down: Long Unwinding
- Adds, edits, searches, filters by date, and deletes trade journal entries.
- Calculates realised P&L as (exit - entry) × quantity for BUY and (entry - exit) × quantity for SELL, less charges.
- Exports journal data to CSV and generates PDF reports.
- Builds a WhatsApp-ready tip with instrument, action, entry, stop-loss, targets, and analysis. Android share sheet lets the user choose WhatsApp and send manually.
- Trade journal data is stored locally on the device using SharedPreferences.

## Important market-data notes

The supplied CSV contains `CHNG` and `CHNG IN OI` fields. The app uses those exchange-provided changes to classify positioning at each strike. It does not infer a guaranteed market direction or generate guaranteed buy/sell calls. CE and PE contract positioning is shown separately because the market implication differs by contract type. The app currently does not connect to a broker, fetch live prices, or place orders. The imported file must be a compatible option-chain export.

## Build locally

Install Flutter stable and Android SDK, then from this project directory run:

```bash
flutter create --platforms=android --org com.tradepulse.app .
flutter pub get
flutter run
```

Build APK:

```bash
flutter build apk --release
```

APK output:
`build/app/outputs/flutter-apk/app-release.apk`

## Build with Codemagic

1. Upload this project folder to a Git repository.
2. Connect the repository in Codemagic.
3. Select `codemagic.yaml` as the workflow configuration.
4. Start `TradePulse OI - Android APK`.
5. Download `app-release.apk` from the build artifacts.

The workflow generates the standard Android platform folder using Flutter before building. No signing configuration is needed for a test APK. Configure Android release signing in Codemagic before Play Store distribution.

## Permissions / platform behavior

File selection uses Android's system document picker. CSV and PDF exports use Android's share sheet / printing flow. WhatsApp sharing requires WhatsApp to be installed; otherwise choose another available share target. The app never sends a message without the user's confirmation.

## Suggested next production upgrades

- Add secure cloud backup and multi-device sync.
- Add broker-specific CSV profiles and automatic column mapping for other formats.
- Add snapshot archive with visual OI build-up comparison over time.
- Add live market-data integration through a licensed broker/data provider.
- Add configurable risk-per-trade, position sizing, brokerage/tax calculations, and portfolio-level analytics.
