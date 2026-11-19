# Wild Circuits Team Hub

Native iPhone and iPad workspace for FIRST Tech Challenge team **36611**. Requires iOS 17 or later.

| Screen | What you can do |
| --- | --- |
| Today | See the next team match, readiness, critical issues, tasks and inventory alerts. |
| Compete | Choose a season and event, browse matches and rankings, compare teams, and save match plans. |
| Scout | Save match drafts, review and submit locally, capture pit reports, plan your own scouting coverage and export match reports to CSV. |
| Work | Track tasks and owners, keep engineering notes and resource links, and record ideas. |
| Pit | Log and resolve robot issues, edit readiness templates, run match-specific checks and manage inventory. |
| Settings | Set appearance, add local contacts, check data freshness and manage your session. |

## Build

On macOS with Xcode 26 and XcodeGen:

```shell
xcodegen generate
open FTCTeamHub.xcodeproj
```

To archive and package an unsigned iPhone build:

```shell
bash scripts/build-unsigned-ipa.sh
```

GitHub Actions runs **Build unsigned iOS IPA** and uploads the archive with a SHA-256 checksum. The packaging script checks the Mach-O executable, unsigned state and ZIP integrity. Sign the IPA with a compatible signing method before installation on a standard iPhone.

Run the test suite on a locally installed iPhone simulator with `bash scripts/test-ios.sh`. The simulator job uploads logs and XCTest screenshots.

## Google Sign-In

The app keeps the original bundle identifier, `com.ftcteamhub.app`, and Google Sign-In SDK. For a configured build, set the iOS OAuth client ID via `GIDClientID` in `Resources/Info.plist` and the reversed client ID in `CFBundleURLTypes`. Both must come from the same Google iOS client. The Google button appears when this configuration is valid. **Use On This Device** opens a separate workspace with no Google account required. Sign in with the same Google account to return to its workspace.

## Records and compatibility

- SwiftData stores workspace records on the device. Report drafts and checklists remain editable offline after setup. Each Google account and the on-device workspace use separate stores.
- The upgrade keeps the original data models and matches the original store to a Google identity only when authored notebook, scouting or idea records consistently identify that account. Unattributed or mixed-author stores are left intact for manual recovery. Preserve the original store and its SQLite sidecars before any recovery.
- FTCScout public data is cached on disk after a successful decode. Cached data appears on a failed refresh and is labeled with its fetch time where relevant. A first-time event download requires a connection.
- Match drafts are keyed by season, event, FTCScout match ID, observed robot and scout. The same key opens the existing draft. On-device submission is an explicit reviewed state. Older reports and scores retain their original format and remain exportable.
- BIOBUZZ reports record observations about one robot. Alliance scores and FTCScout OPR estimates are displayed in the competition workspace with source and context. For other seasons, the form supports phase-specific notes.

## Current deployment scope

The repository has no collaboration backend, roster authorization service, cloud queue, push service or image storage. Contacts, scout assignments, reports, plans, readiness and other work stay in the current workspace. CSV exports use the system file picker. An authenticated Google identity identifies a local workspace. Team invitations, remote roles and multi-device sharing require a trusted backend before they can be enabled.

The app uses the [original Team Hub app icon](https://github.com/FTC-wildcircuits/FTC-2026-2027/tree/main/FTCTeamHub/Assets.xcassets/AppIcon.appiconset) from the Wild Circuits team repository alongside the verified team name and number. A separate official team logo was unavailable.

## References

- [Official FIRST team profile](https://ftc-events.firstinspires.org/2026/team/36611)
- [FIRST BIOBUZZ game rules](https://ftc-resources.firstinspires.org/ftc/game/manual-10)
- [FTCScout API](https://ftcscout.org/api) and [provider implementation](https://github.com/ftc-scout/ftc-scout)
- [Apple tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields), [Apple Sports](https://support.apple.com/guide/apple-sports-app/apdec6a74b4c/web) and [Reminders](https://support.apple.com/guide/iphone/iph82596cb20/ios)
