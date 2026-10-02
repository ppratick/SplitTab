# SplitTab

A SwiftUI iOS app for splitting a shared bill. Scan a receipt into editable line
items or enter items manually, assign purchases to participants, and reconcile
each person's share with the bill total.

## Features

- Camera capture and optional GPT-4o receipt extraction with manual corrections.
- Itemized and equal splits, including items shared by multiple people.
- Taxes, tips, fees, and discounts allocated across participants.
- Decimal currency calculations and rounding-remainder reconciliation.

## Build and run

Requires macOS, Xcode 26.4 or newer, and an iOS 26 SDK. The project targets iOS 26.
There are no third-party package dependencies.

```sh
git clone https://github.com/ppratick/SplitTab.git
cd SplitTab
open SplitTab.xcodeproj
```

Select the **SplitTab** scheme and an iPhone simulator, then run. Manual receipt
entry and bill splitting work without an API key. For a physical device, choose
your own development team in **Signing & Capabilities** and a unique bundle
identifier. Camera behavior needs a physical-device check.

To compile for the simulator without signing:

```sh
xcodebuild -project SplitTab.xcodeproj -scheme SplitTab \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Optional AI receipt scanning

`Config/ReceiptScanning.env.example` lists the single optional environment
variable. The app reads `OPENAI_API_KEY` from its launch environment; it does
not read `.env` files or require the old ignored `Constants.swift` file. The
Xcode target also excludes `Constants.swift` so an existing local legacy key
file is not compiled into the app.

1. In Xcode, open **Product → Scheme → Manage Schemes** and keep your development
   scheme **unshared** so its settings stay in ignored `xcuserdata`.
2. Open **Product → Scheme → Edit Scheme → Run → Arguments**.
3. Add an enabled environment variable named `OPENAI_API_KEY` with your own key.
4. Launch from Xcode. API requests use your account and may incur charges.

Without a key, scanning fails locally with a setup message before sending a
request; manual entry remains available. AI scanning sends the receipt image
to OpenAI, so use receipts you have permission to process and review extracted
values before splitting.

Do not commit credentials, share a scheme containing them, or embed a developer
key in an app binary. A publicly distributed app should use an authenticated
backend for provider credentials. This repository provides a local development
workflow; it does not provide that production backend.

## Validation scope

The repository has no XCTest target or configured CI. A simulator build checks
compilation; it does not verify camera behavior, live API extraction, or real
receipt accuracy. Receipt values remain editable because extraction can fail.
