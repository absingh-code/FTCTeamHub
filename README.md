# Wild Circuits Team Hub

Native SwiftUI app for FIRST Tech Challenge on iOS 17 or later. Version 1.2, build 3. The shared workspace requires Firebase Authentication and an active team membership. Wild Circuits is FTC team 36611. [FTCScout team record](https://api.ftcscout.org/rest/v1/teams/36611) · [FIRST team page](https://ftc-events.firstinspires.org/team/36611)

## Feature parity and verification

The baseline is PR #1 at `9aa2fce`. It added competition and pit workflows, a dual-appearance design system, account-scoped SwiftData stores and reproducible iOS CI. The default branch at `c9c98b1` was inspected for regressions and the original model and feature behavior. The team-provided repository at `4aa3c13` was inspected for its app asset, existing back end and independent data model. [Original app](https://github.com/absingh-code/FTCTeamHub/tree/c9c98b16e0effbca3efc8a35422b993f7f09c3d1) · [Previous upgrade](https://github.com/absingh-code/FTCTeamHub/pull/1) · [Team reference](https://github.com/FTC-wildcircuits/FTC-2026-2027/tree/4aa3c130ed878f46e53eb0acc1d6164d5e0d9615)

| Feature | Original behavior | Previous upgrade behavior | 1.2 implementation and verification |
| --- | --- | --- | --- |
| Identity | Google SDK mapped an iOS account to a local profile. Plist used OAuth placeholders. | Optional Google profile with separate local store. Device workspace was offered at sign-in. | Firebase credential exchange, session listener, account switching via sign-out and Google-branded login. Live Google exchange and restoration require the configured iOS client. Auth emulator checks use two independent SDK identities with mock provider credentials. |
| Team and roster | Local SwiftData roster list. No verified membership. | Local contacts and settings. | Active memberships, invite acceptance, roles, roster, team selection and revocation. Firestore rules and invitation batches exercised in the emulator. |
| Chat | Placeholder conversation backed by an in-memory array. | Chat removed. | Team conversation with server timestamps, newest-page listener, older-page cursor, durable outbox, composer and retry. Emulator confirms delivery between distinct identities and denies spoofed sender, viewer writes and revoked access. |
| Announcements | Missing. | Missing. | Coordinator-only posts with optional HTTPS resources. Latest post appears on Today. Emulator checks role restrictions. |
| Today | Local tasks, upcoming team events, inventory alerts. | Added active event, next match, readiness and critical issues. | Uses team-scoped records and actual team number. Added team entry, announcement and sync state. Populated simulator fixtures cover layout. |
| Tasks | Local statuses, assignment IDs and notes. | Search, priority, deadlines and local contacts. | Real roster assignment, shared task statuses and existing filters. Two emulator sessions covered bidirectional edits, stale revision denial and offline replay. |
| Engineering notebook | Local entries and templates. | Expanded decision, test, meeting, outreach and resource templates. | Existing templates and search on shared records. Structured robot configuration and autonomous trial libraries are deferred. |
| Ideas | Local vote tally could be incremented repeatedly. | Local counter remained. | Per-member vote document with reversible vote and independent concurrent voters. Rule tests cover vote ownership. |
| Inventory | Local stock, thresholds, maintenance and QR placeholder. | Search, location, editable counts and maintenance status. | Shared item, atomic attributed quantity changes and searchable stock. Emulator validates paired inventory history. QR, battery tracking, loan tracking and packing assignments are deferred. |
| Competition | Basic FTCScout team and event queries. | Added rankings, schedules, profiles, match results, comparisons and caching. | Preserves those views and connects historical event participation to rankings, matches and teams. Match detail includes available alliance breakdowns and profiles. |
| Scouting and export | Local reports and CSV. | BIOBUZZ schema, local drafts, submission, pit reports and CSV. | Private drafts, shared submissions and corrections, pit reports and CSV. Stable keys include match, team and scout. Rule tests cover duplicates, invalid counts and authorization. |
| Scouting coordination | Missing. | Self-assignment with coverage gaps. | Team assignments and coordinator roster selection from a match. Coverage and report state read the shared records. Dedicated coordinator review and observation adjudication are deferred. |
| Strategy | Missing. | Local match plan, auto notes and partner pit observations. | Shared match plan and linked match/issues. Ranked pick lists, watchlists and dedicated debrief templates are deferred. |
| Pit workflow | Local maintenance status. | Issue resolution and separate editable readiness runs. | Shared issue owners and readiness records, existing state machine and linked matches. Simulator smoke tests exercise issue resolution and separate readiness runs. |
| Appearance | Dark mode only. | Light, dark and system with shared SwiftUI tokens. | Refined team entry and navigation, distinct login/chat/profile/scouting layouts and fixture-only screenshot paths. |
| Data recovery | SwiftData default store. | One store per Google subject or device-only workspace. | Existing stores remain in place. A verified owner can export a previous account store as JSON from Settings. Existing remote data requires an explicit migration. |

## Configure Google and Firebase

The team reference app uses the bundle ID `com.ftcteamhub.app` and has a Firebase registration plist. Its checked-in plist lacks both `CLIENT_ID` and `REVERSED_CLIENT_ID`. Its existing sync service uses root-level collections and a separate local account schema. Verify or migrate applicable team data before switching clients. [Team Firebase setup](https://github.com/FTC-wildcircuits/FTC-2026-2027/blob/main/FIREBASE_SETUP.md)

1. In a staging Firebase project, register the Apple app with bundle ID `com.ftcteamhub.app`. Enable **Authentication → Sign-in method → Google** and select its support email. Download a fresh iOS `GoogleService-Info.plist`. Confirm the iOS OAuth client and reversed scheme appear in it. [Firebase Google setup for Apple platforms](https://firebase.google.com/docs/auth/ios/google-signin)
2. Place the plist at the gitignored `Resources/GoogleService-Info.plist` locally. For the archive workflow, add its base64 encoding as the repository Actions secret `FTCTEAMHUB_FIREBASE_PLIST_BASE64`. The configure script validates the IDs and injects the callback scheme into the build copy of Info.plist. Generate or archive from a clean checkout.
3. Create Firestore in the target staging project and deploy the checked-in rules and indexes. Review existing uses of the project's Firestore rules before replacing them. The included rules authorize the new workspace namespace. The prior reference app uses other collections.
4. Launch the configured build and sign in with the intended initial mentor's Google account. Use its Firebase UID for a trusted setup operation. Create these documents with the Firebase Admin SDK or Firebase Console.

| Document | Fields |
| --- | --- |
| `workspaces/{workspaceID}` | `name` string `Wild Circuits`, `number` integer `36611` |
| `workspaces/{workspaceID}/members/{firebaseUID}` | `name` string, `role` string `admin`, `active` boolean `true`, `joinedAt` timestamp |
| `workspaceUsers/{firebaseUID}/memberships/{workspaceID}` | `joinedAt` timestamp |

Choose a lowercase workspace ID using letters, digits and hyphens, 4 to 64 characters. The workspace code helps users find an invitation. Access requires a matching verified Google email and a successful atomic membership write. Administrators and mentors can invite members, scouts and viewers. Privileged role provisioning uses trusted administration.

Take the staged build through sign-in, restoration, membership, chat, shared tasks, scouting submission, reconnection and revocation with two real Google accounts before rollout. Cross-device evidence from the emulator covers SDK and rules behavior with synthetic identities.

## Shared storage and migration

- Firestore is authoritative for team records, roster, votes and chat. The iOS projection and outgoing queue are scoped by Firebase project, account and team. Firestore's client cache is memory-only. The app checks authorization with the server before opening private content after an app restart.
- The durable queue writes one operation ID before confirming a local write. Firestore checks record revisions, attributes the actor and timestamps updates. Inventory quantity changes and history commit together. Chat uses stable IDs for resend. A revision conflict pauses writes to that record. Sync shows retry and discard controls.
- Unsubmitted match reports are private SwiftData drafts, and the previously shared revision remains visible to teammates during a correction. Outgoing records and drafts persist through a restart. A new private session needs connectivity to recheck membership and open the workspace. Chat history loads in pages of 40 and stock history shows the latest 25 changes.
- To recover a previous Google-scoped local store, use **Settings → Legacy records → Export Previous Workspace** while signed in with that Google account on the original device. The JSON includes records and drafts, legacy scouting fields and local contact labels. It omits credentials. A single-account original store is recognized only when ownership can be established. The device-only store has no verified account owner and needs an explicitly reviewed migration from the original device.
- For the team reference back end, first take an administrator backup and inventory which records were actually written. Resolve each prior roster ID to a verified Firebase UID. Preserve source IDs, event/season, authorship and original dates where they can be established. Review and import as an administrator into the new tenant. Exclude password hashes, tokens and unverifiable membership fields. Legacy root data is not imported by the app.
- Validate imported totals and task assignments with real members before adoption. Keep the old database export and scope change separate from any rollback of the new iOS binary.

## Native design and public FTC data

The app uses native navigation, type, accessibility settings and appearance, with a compact team mark and restrained accent. Reminders' grouped work lists informed task filters. Messages informed the bottom composer and inline retry. Apple Sports informed the transition from a compact score row to a match detail. Apple's data-entry guidance informed grouped scouting controls and review before submission. The Mobbin public index was available, and individual screens were unavailable for review. The app mark matches the supplied team's app asset byte for byte. [Reminders lists](https://support.apple.com/en-mide/guide/iphone/iph2c6cf708e/ios) · [Messages conversations](https://support.apple.com/guide/iphone/send-and-reply-to-messages-iph82fb73ba3/26/ios/26) · [Apple Sports schedules and scores](https://support.apple.com/en-au/guide/apple-sports-app/apd5a38547d1/web) · [Apple data entry](https://developer.apple.com/design/human-interface-guidelines/entering-data) · [Mobbin iOS index](https://mobbin.com/discover/apps/ios) · [Team-owned app icon](https://github.com/FTC-wildcircuits/FTC-2026-2027/tree/main/FTCTeamHub/Assets.xcassets/AppIcon.appiconset)

FTCScout is the public provider. REST covers team identity, event matches and participation, and GraphQL covers connected event and roster queries. Identity keys use team number, provider season start year, uppercase event code and match ID. Match breakdowns are alliance totals and OPR is an external estimate. Scouting observations have their own source, sample and season. Failed refresh may use previously fetched public data with a fetch date. FIRST's API requires a username/token and has use restrictions, so this client uses FTCScout with no embedded FIRST credentials. The BIOBUZZ form follows the current FIRST game manual and preserves its schema identifier. [FTCScout API](https://ftcscout.org/api) · [FIRST API policy](https://ftc-events.firstinspires.org/services/API) · [BIOBUZZ game details](https://ftc-resources.firstinspires.org/ftc/game/manual-10)

## Build and verify

macOS with Xcode and XcodeGen is required for the native build.

```bash
python3 scripts/configure-firebase.py
xcodegen generate
bash scripts/test-ios.sh
bash scripts/build-unsigned-ipa.sh
```

The unsigned archive workflow provides the IPA, SHA-256 digest, build log and commit identity. The simulator workflow exports screenshots from isolated debug fixtures. An unsigned IPA requires appropriate signing and provisioning for a normal iPhone.

Run the rule and cross-session tests with the Firebase emulators.

```bash
pnpm --dir firebase install --frozen-lockfile --ignore-scripts
firebase/node_modules/.bin/firebase emulators:exec --only firestore,auth --project demo-ftcteamhub 'node --test firebase/workspace.test.mjs'
```

The collaboration tests cover invitation and tenant isolation, two independently authenticated emulator sessions, message and task delivery, offline update, duplicate reports, per-user votes, stock history and revocation. Release verification also needs a configured build, real accounts and a live Firestore project.

On macOS, the simulator workflow seeds its own synthetic team and also tests two native Firebase iOS SDK sessions. It checks the SwiftData projection, chat delivery and restoration of the app's durable queue after reopening an offline workspace.

```bash
firebase/node_modules/.bin/firebase emulators:exec --only firestore,auth --project demo-ftcteamhub 'node firebase/seed-native.mjs && bash scripts/test-ios.sh'
```

## Deferred work

Push notifications, read receipts, photo and attachment storage, full account deletion, broader migration tooling, an autonomous routine library, watchlists and ranked pick lists, a dedicated debrief workflow and private strategy-note permissions require additional implementation and verification.
