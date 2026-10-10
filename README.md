# FTC Team Hub

Native iOS 17+ SwiftUI app for FIRST Tech Challenge team management, scouting, and collaboration.

## Design rules (enforced)

- Dark mode only (`preferredColorScheme(.dark)`)
- Native `TabView` — Today, Work, Pit, Scout, Team
- Asset-backed colors only (see Assets.xcassets notes below)
- SF Pro semantic typography
- List / Form first, continuous corner radii
- No gradients, glows, neon, emoji, slogans, fabricated metrics, custom tab bars
- Loading / empty / error / offline states on every data screen
- Role labels never contain the word “Lead” (use “Software”)

## Features

- **Today** — assigned tasks, upcoming events, inventory alerts
- **Work** — tasks (status columns), engineering notebook with templates, ideas + upvotes
- **Pit** — searchable inventory, low-stock thresholds, maintenance status, QR scanner placeholder
- **Scout** — local match reports with large steppers, CSV export, real FTCScout GraphQL client (honest errors)
- **Team** — roster, Google Sign-In identity, basic chat (opt-in Firebase ready)
- SwiftData persistence
- Google Sign-In
- Haptic feedback on meaningful actions

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) or open in Xcode and add the sources manually.
2. Run `xcodegen` in this folder to generate the `.xcodeproj`.
3. Add the six color sets in Assets.xcassets (dark values only):

| Name           | Hex     |
|----------------|---------|
| Background     | #0A0C0F |
| Surface        | #12161B |
| Raised         | #1A2027 |
| Hairline       | #FFFFFF @ 8% |
| Scrim          | #000000 @ 25% |
| LabelPrimary   | #F2F4F7 |
| LabelSecondary | #8E99A5 |
| LabelTertiary  | #5C6672 |

4. Replace `YOUR_GOOGLE_CLIENT_ID` and the reversed client ID in `Resources/Info.plist`.
5. Build and run on iOS 17+.

## Google Sign-In

1. Create an OAuth client in Google Cloud Console (iOS type).
2. Put the client ID in Info.plist under `GIDClientID`.
3. Put the reversed client ID as a URL scheme under `CFBundleURLTypes`.

## Building an unsigned IPA

Use the existing GitHub Actions workflow in your repository, or locally:

```bash
xcodebuild -scheme FTCTeamHub -configuration Release -sdk iphoneos -archivePath build/FTCTeamHub.xcarchive archive CODE_SIGNING_ALLOWED=NO
# Then package the .app from the archive into an IPA
```

The resulting IPA has no signature and must be signed with a sideloading tool (Sideloadly, AltStore, TrollStore, etc.) before installation.

## Architecture

- MVVM
- SwiftData models
- `@Observable` view models
- Native navigation only
- Real network errors surfaced; no fake live data
