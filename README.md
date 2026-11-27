# TradePulse OI — Android Trading Journal & Snapshot Analyzer

Flutter Android application for trading records, option-chain CSV uploads, point-in-time snapshot comparisons, CE/PE strike lookup, reports, and shareable trade setups.

## What's new in this upgrade

- **Snapshot-to-snapshot comparison:** the first CSV is saved as a baseline. Each subsequent CSV is compared with the immediately previous upload.
- **CE and PE signals are calculated independently** at every matching strike.
- **Strike lookup:** enter a strike price (for example, `26000`) to see the CE and PE market-position labels, premium delta, OI delta, latest LTP and latest OI.
- **Strike list:** tap any compared strike to open its detailed CE/PE status.
- **Local snapshot persistence:** the latest 10 CSV snapshots are retained on the device using SharedPreferences and restored when the app is reopened.
- **More resilient Android import:** the document picker accepts files from different Android document providers, reads the selected file as a byte stream, and falls back to available bytes or a local cached path. The app validates the `.csv` extension and displays actionable import errors.
- **Header-based CSV mapping:** the parser locates the `STRIKE` heading and resolves CALL and PUT fields on either side of it. It handles the supplied 23-column NSE-style layout, CRLF/LF line endings, BOM, Indian comma-formatted numbers, and `-` empty values.

## OI classification logic

The app compares **current LTP against previous LTP** and **current OI against previous OI**. It does not use the CSV's day `CHNG` fields as the snapshot delta.

| Premium delta | OI delta | Classification |
|---|---|---|
| Down | Up | Short Build-up |
| Up | Down | Short Covering |
| Up | Up | Fresh Long Build-up |
| Down | Down | Long Unwinding |
| No clear directional change | Any | Neutral / No clear signal |

The same four labels are calculated separately for CE and PE. The directional interpretation differs by contract type: fresh CE longs are generally bullish CE positioning, while fresh PE longs are generally bearish PE positioning.

## Upload workflow

1. Open **OI Analyzer** and upload a compatible option-chain `.csv` file. This is the baseline; no comparison signal is expected yet.
2. Later, upload the next CSV for the same underlying and expiry.
3. The app matches identical strike prices between the two snapshots and calculates the LTP and OI deltas.
4. Enter a strike such as `26000` under **Check a particular strike**, then tap **Check**. CE and PE results are displayed side by side.
5. The list below the positioning guide shows every matching strike. Tap a row to load its detailed result.

For best comparisons, upload files for the same underlying, expiry, and option-chain layout. If a strike or a side's LTP/OI is missing from either file, that side is marked insufficient rather than inventing a signal.

## Other features

- Dashboard with trade count, realised P&L and win rate.
- Add/edit/delete trade records.
- Search journal records and filter by date range.
- CSV export and PDF report generation.
- WhatsApp/share-sheet trade setup with action, entry, stop-loss and targets. The app prepares the message; the user confirms and sends it.
- Trade journal and OI snapshots are stored locally on the device. This build does not use MongoDB or broker cloud sync.

## Build locally

Install Flutter stable and Android SDK, then run from this project directory:

```bash
flutter create --platforms=android --org com.tradepulse.app .
flutter pub get
flutter run
```

Build APK:

```bash
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

## Build with Codemagic

1. Push this project folder to GitHub.
2. Connect the repository in Codemagic.
3. Select the included `codemagic.yaml` workflow.
4. Run **TradePulse OI - Android APK**.
5. Download `app-release.apk` from build artifacts.

The workflow regenerates the Android platform folder, sets `compileSdk` to 36, resolves packages, and builds the release APK. This source package has not been compiled in this environment because the Flutter SDK is not installed here; run Codemagic to perform the actual Android build.

## Market-data limitations

This is an offline CSV analysis tool. It does not fetch live prices, place orders, or guarantee market direction. A signal indicates how premium and OI changed between the two selected upload snapshots. It can become stale as soon as the market moves; upload a newer option-chain CSV for an updated comparison. Use appropriate risk management and independently verify the market before trading.
