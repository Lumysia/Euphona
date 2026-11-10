# Developing Euphona

How the project is laid out and how to build, test, translate and release it. Why things are the
way they are is in [`decisions.md`](decisions.md); product direction in [`roadmap.md`](roadmap.md);
known gaps in [`queue.md`](queue.md).

## Layout

| Path | What it holds |
| --- | --- |
| `Euphona/` | The app for iPhone, iPad and Mac: screens, design system, app wiring |
| `Packages/EuphonaKit/` | Everything that isn't a screen: the analysis engine, scoring, Coach planning, history, settings; tested with `swift test` |
| `Packages/EuphonaKit/Sources/Models/` | The ONNX models the engine runs, with their sources and licences |
| `tools/strings/` | All interface text and its translations, and the scripts that build the String Catalogs |
| `tools/voice-model/` | Training and evaluation of Euphona's own models (a `uv` project) |
| `tools/screenshots/` | Simulator and Mac screenshots for review |
| `tools/ci/` | Build and release-notes scripts used by GitHub Actions |

## Build and run

Xcode 27 or later. Open `Euphona.xcodeproj`, pick a device, Run. From the command line:

```sh
xcodebuild -project Euphona.xcodeproj -scheme Euphona -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData -allowProvisioningUpdates build
xcrun devicectl list devices
xcrun devicectl device install app --device <device-id> .build/DerivedData/Build/Products/Debug-iphoneos/Euphona.app
```

On Mac, build with `-destination 'platform=macOS'`; the app is in
`.build/DerivedData/Build/Products/Debug/Euphona.app`. The Mac store is the person's real, iCloud-synced
history, so demo data is never seeded there.

## Tests

`cd Packages/EuphonaKit && swift test` runs the package tests (engine, scoring, Coach, history). CI runs
them and builds the app for iOS and macOS on pull requests and `main`.

## Screenshots

`tools/screenshots/capture.sh ["iPhone 17"]` installs the simulator build (build it first), seeds demo
analyses and saves one screenshot per screen under `.build/shots/`. Options: `SCREENS="coach rules"`,
`APPEARANCE=dark`, `PALETTE=ocean`, `LANGUAGE=de`. `tools/screenshots/capture_mac.sh <name> [-demo_screen <name>]`
captures the Mac windows. Development builds also take `-demo_export <folder>` (writes every image and
PDF export) and `-demo_message <text>` (sends a Coach chat message).

The README's `docs/images/iphone.png` is built from those shots:

```sh
S=.build/shots/iPhone-17
swift tools/screenshots/overview.swift docs/images/iphone.png 6 360 \
  $S/{today,analysis,result,rules,progress,coach,lesson,lesson-intro,practice,resonance,piano,settings}.png
```

## Text and translations

All text is in `tools/strings/strings.json` (English and Simplified Chinese) and
`tools/strings/translations/<code>.json` (one file per other language), with plural forms in
`plurals.json`, Mac wording in `mac.json` and permission prompts in `infoplist_strings.json`. After a
change:

```sh
tools/strings/build_strings.py          # writes Euphona/Localizable.xcstrings and InfoPlist.xcstrings
tools/strings/check_translations.py check
```

The build reports any language missing a key; the check validates every translation's format
specifiers against the English.

## Models

`tools/voice-model/` (`uv run python <script>`): `extract.py` and `fleurs.py` build the training data,
`train.py` the timbre head, `train_ease.py` the ease model, `flow.py` calibrates flow,
`train_quality.py` the Voice Quality model, `score.py` scores recordings through the app's path. Data
and results stay under the git-ignored `.build/voice-model/`. A shipped model change bumps
`EuphonaAnalyzer.modelVersion`, which re-analyzes saved recordings at launch.

## Releases

1. Move the `Unreleased` part of `CHANGELOG.md` under the new version's heading and bump the version.
2. Squash-merge to `main` with a Conventional Commit subject (`feat: <summary> (vX.Y.Z)`).
3. When CI is green on that commit, push the tag: `git push origin refs/tags/vX.Y.Z`. The release
   workflow publishes a GitHub release with that changelog section, and archives, signs and uploads
   the iOS and macOS builds to App Store Connect (`tools/ci/upload.sh`), build number = the run number.
4. In App Store Connect, pick the build for the version and submit it for review.

The upload needs three repository secrets from an App Store Connect API key with the Admin role
(Users and Access → Integrations): `APP_STORE_CONNECT_KEY` (the `.p8` file's contents),
`APP_STORE_CONNECT_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID`. Xcode's cloud-managed signing creates the
distribution certificate and profiles from it, so none are stored in the repository.
