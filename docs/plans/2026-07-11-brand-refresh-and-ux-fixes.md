# Plan: Whole-card expand, Likes-tab logic fix, primary Send-message CTA, red/blue brand refresh, App Store metadata for release

Date: 2026-07-11. All app work in `/Users/tashitsering/Desktop/Projects/drokpo-app`. **No backend changes needed.**
Prereq facts discovered during planning (do not re-derive):

- The Xcode project is generated: after adding/removing files run `xcodegen generate` (installed at `/opt/homebrew/bin/xcodegen`), then build with `xcodebuild -project Drokpo.xcodeproj -scheme Drokpo -destination 'generic/platform=iOS Simulator' build`.
- `Logo.imageset` is **template-rendered** (`"template-rendering-intent": "template"` in its Contents.json) and tinted by `.foregroundStyle(.tint)` in SignInView — today it renders in the maroon accent.
- Current AccentColor is Tibetan maroon (`#AF424A`-ish, with a lighter dark variant). App icon is a cream handshake on a maroon gradient; `Logo.png` is a 560×560 cream handshake with transparent background (RGBA — its alpha channel is a clean mask of the handshake glyph).
- Pillow is NOT installed for system python3 (and macOS python is externally managed) — any image script must run in a venv (create it in the session scratchpad dir, not the repo).
- App Store Connect API key: `~/Downloads/AuthKey_DFDRX9AW9K.p8` (Admin role), key id `DFDRX9AW9K`, issuer id `740fa955-2ad0-4d4c-a447-c67f9c446977` (same key CI uses; see `.github/workflows/testflight.yml`). Bundle id `app.drokpo.ios`. The app has **never been released** — `MARKETING_VERSION` is `1.0` and the ASC version record 1.0 should be in an editable (Prepare for Submission) state. Do **not** bump MARKETING_VERSION.
- Canonical listing copy lives in `AppStore/metadata.md` — update it first, then push to ASC.

---

## 1 — Tap-to-expand should work on the whole Discover card, not just the bottom

Current state ([CardView.swift](../../Drokpo/Features/Feed/CardView.swift)): when a card has >1 photo, two full-height invisible tap zones (left half = previous photo, right half = next photo) cover the whole photo, so the only expand taps that land are on the bottom info block. With ≤1 photo there are no zones at all, and the photo area does nothing.

Change in `CardView` (it already sits in a `GeometryReader`, so `geometry.size.width` is available):

- **Multiple photos**: replace the two-zone `HStack` with three zones —
  left `0.30 × width` = previous photo, center (flexible) = `onExpand?()`, right `0.30 × width` = next photo. Full height, `Rectangle().fill(.clear).contentShape(Rectangle())` each, same as today.
- **0–1 photos**: add a single full-area clear tap zone → `onExpand?()` (today's `photos.count > 1` guard means this case currently has no zones; give it one).
- Keep the existing info-block `.onTapGesture { onExpand?() }` and the chevron affordance — the ZStack ordering already puts the info block above the zones so its tap wins there.
- `onExpand` stays optional and is only non-nil for the top card (already wired in `SwipeableCard`), so background cards and non-Discover uses are unaffected. Verify the safety `ellipsis` button still receives its tap (it's in the info block, above the zones — should be fine, but tap it once in the simulator).

## 2 — Fix the Likes-page logic (duplication + wrong CTA)

Two real bugs in [LikesView.swift](../../Drokpo/Features/Likes/LikesView.swift):

1. **Matched people appear in both tabs.** Once you match, your outgoing like and their incoming like both still exist, so the same person shows under "Liked you" AND "You liked", both with a "Matched" pill — pure noise, since matched people already live in Chats (the "New matches" row and conversation list).
2. **Both tabs pass the same `.likedYou` context** to `ProfileDetailView`, so a profile opened from "You liked" shows a "Like back" button — nonsense for someone you already liked.

Fix — the rule becomes: *Likes shows pending likes only; matched people live in Chats.*

- In `load()`, after decoding, filter both lists: `received.removeAll { $0.isMatched }` and `given.removeAll { $0.isMatched }` (backend already sends `matchId`/`matchStatus`; `isMatched` is on `SwipeEntry`).
- Delete the now-dead "Matched" pill from the row, and drop the `!entry.isMatched` condition on the heart button (every visible received entry is now unmatched).
- Context per tab:
  - `direction == .received` → `ProfileDetailView(card:context: .likedYou(onLikeBack: { await likeBack(card) }))`
  - `direction == .given` → `ProfileDetailView(card:)` (plain, read-only — you've liked them; nothing to do but wait).
- Simplify the context enum: `.likedYou(matchId:onLikeBack:)` → `.likedYou(onLikeBack:)`. The `matchId` parameter is now always nil (matched entries never reach the list), and the post-like-back "Send message" state already comes from `localMatchId` inside `ProfileDetailView`. Update the one construction site.
- Empty-state copy for "You liked" can stay; for "Liked you" it's still accurate.

## 3 — "Send message" as a real primary button

In [ProfileDetailView.swift](../../Drokpo/Features/Shared/ProfileDetailView.swift), the `likedYou` action bar buttons are default-size `borderedProminent` — visually small. Make both CTAs full-width primaries:

```swift
// Send message (after a like-back match):
Button {
    openThread(matchId: activeMatchId)
} label: {
    Label("Send message", systemImage: "bubble.left.fill")
        .font(.headline)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
}
.buttonStyle(.borderedProminent)
.controlSize(.large)
// tint: default accent (brand blue after §4)

// Like back:
same shape, Label("Like back", systemImage: "heart.fill"), .tint(.brandRed)
```

Both sit in the existing `.safeAreaInset(edge: .bottom)` bar with `.padding(.horizontal)`. The match alert's "Say hi" already deep-links to the thread — unchanged. (Profiles opened from a chat thread keep `.plain` — you're already in the conversation, no CTA needed.)

## 4 — Brand refresh: YouTube red + Facebook blue

Brand definition (put the rationale in a comment in Brand.swift): **blue `#1877F2` is the app's primary/accent** (buttons, links, chat bubbles, selected tabs, sign-in logo tint); **red `#FF0000` is reserved for like/love actions** (hearts, like buttons, LIKE stamp).

### 4a. Color assets + Swift constants

- Rewrite `Drokpo/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`: light `#1877F2` (r 0.094, g 0.467, b 0.949), dark variant `#4599FF` (r 0.271, g 0.600, b 1.0 — lighter for contrast on dark backgrounds). Keep the same two-entry structure the file already has.
- New colorset `BrandRed.colorset`: light `#FF0000` (r 1, g 0, b 0), dark variant `#FF3B30`-ish (r 1, g 0.271, b 0.227) so pure red doesn't vibrate on black.
- New file `Drokpo/Core/Brand.swift`:
  ```swift
  extension Color {
      /// Like/love actions only — everything else uses the accent (brand blue).
      static let brandRed = Color("BrandRed")
  }
  ```
  (Blue needs no constant — it IS the accent; use `.tint`/default prominence everywhere.)

### 4b. Replace hardcoded colors (complete inventory, verified by grep)

| File:line (pre-change) | Now | Becomes |
|---|---|---|
| `SwipeActionButtons.swift:19` like heart | `.pink` | `.brandRed` |
| `SwipeActionButtons.swift:18` pass X | `.red` | `.accentColor` (blue) — red now means "like", so the X must not be red |
| `FeedView.swift:126` LIKE stamp | `.green` | `.brandRed` |
| `FeedView.swift:127` PASS stamp | `.red` | `.blue` accent — use `Color.accentColor` |
| `LikesView.swift:111` row heart | `.pink` | `.brandRed` |
| `LikesView.swift:96` Matched pill | `.green` | deleted (§2) |
| `ProfileDetailView.swift:129` Like back tint | `.pink` | `.brandRed` |
| `OnboardingFlow.swift:190` checkmark | `.green` | `.tint` (accent blue) |

Everything already on `.tint` / `borderedProminent` (chat bubbles, unread badge, MatchOverlay button, checkmarks, sign-in logo) re-brands automatically via the AccentColor change — no edits.

Also grep once more after changes: `grep -rn "\.pink\|Color.green\|\.green" Drokpo --include="*.swift"` should return only the LIKE-stamp-free results you expect (no stragglers).

### 4c. Regenerate the app icon and logo

Write a one-shot script `ci/make_brand_assets.py` (committed, so the brand can be regenerated later) and run it via a scratchpad venv:

```
python3 -m venv <scratchpad>/venv && <scratchpad>/venv/bin/pip install pillow
<scratchpad>/venv/bin/python ci/make_brand_assets.py
```

The script:
1. Loads the existing `Drokpo/Resources/Assets.xcassets/Logo.imageset/Logo.png` and extracts its **alpha channel** as the handshake mask (the glyph shape is the brand mark — keep it; only the colors change).
2. **AppIcon.png (1024×1024, RGB, no alpha** — Apple rejects transparency): vertical gradient Facebook blue `#1877F2` (top) → `#0E5FCC` (bottom); handshake pasted centered at ~62% of canvas width, painted white via the mask; a solid **red heart** (`#FF0000`, parametric heart curve or two circles + rotated square, ~200px wide) placed at the top-right of the handshake, slightly overlapping it, with a thin white stroke or subtle drop shadow so it separates from the blue. Overwrite `AppIcon.appiconset/AppIcon.png`.
3. **Logo.png (560×560, RGBA)**: same composition without the background — handshake painted `#1877F2`, red heart top-right. Overwrite `Logo.imageset/Logo.png`.
4. Because the logo is now full-color: remove `"template-rendering-intent": "template"` from `Logo.imageset/Contents.json`, and in `SignInView.swift` delete the `.foregroundStyle(.tint)` on `Image("Logo")` (it would be a no-op on an original-render image, but leaving it is misleading).
5. Read both PNGs back with the Read tool (they render as images) to eyeball the result before committing. If the heart placement looks off, adjust and rerun — the script is deterministic.

## 5 — App Store description + push to App Store Connect

### 5a. Update `AppStore/metadata.md`

- **Description**: keep the existing copy's voice; extend the WHY DROKPO bullets to reflect what now exists (all shipped in this release):
  - "Likes that go both ways" bullet → mention you get a notification the moment someone likes you, and can like back or start chatting right from their profile.
  - Add a bullet for full profile detail: "Tap any profile to see everything — photos, region, languages, interests, occupation, and more."
- **What's New (this build)** — replace wholesale (this is release 1.0's story; note whatsNew may not even be submittable on a first release, see 5b):
  ```
  • Get notified the moment someone likes you — tap the notification to see who
  • Like back or send a message straight from their profile
  • Tap any card in Discover to see the full profile
  • It's a match! now takes you straight into the chat
  • Fresh look: new icon and red/blue brand colors
  ```
- **Promotional text / subtitle / keywords**: unchanged unless the user asks.

### 5b. Push to App Store Connect via the API

New script `ci/asc_update_metadata.py` (python; deps `pyjwt`, `cryptography`, `requests` in the same scratchpad venv). A previous session already set the initial listing via this API, and the resource ids are known — hardcode them as defaults (with a `--discover` fallback that re-resolves from the bundle id in case they've changed):

- App id: `6789103137`
- Version 1.0: `5abe0604-bb94-4346-8bb8-0ba235acaef0`, its en-US appStoreVersionLocalization: `64cd7bdd-d3d4-45e6-968d-1e17f3999b2d`
- appInfo: `d58acfa9-b731-4376-bc64-cad7fc29d703`, en-US appInfoLocalization: `72bd73bc-5b35-4246-9379-9e7c089ab8aa`

Behavior:

1. Mint an ES256 JWT: `iss` = `740fa955-2ad0-4d4c-a447-c67f9c446977`, `aud` = `"appstoreconnect-v1"`, `exp` ≤ 20 min, kid `DFDRX9AW9K`, key from `~/Downloads/AuthKey_DFDRX9AW9K.p8` (accept `--key-path` override; the App Manager key `AuthKey_K2J94LT633.p8` also works for metadata if the Admin key is ever revoked).
2. `GET /v1/appStoreVersions/{id}` first and verify `appVersionState`/`appStoreState` is editable (`PREPARE_FOR_SUBMISSION`, `DEVELOPER_REJECTED`, `REJECTED`, `METADATA_REJECTED`, `WAITING_FOR_REVIEW`→not editable). If the hardcoded version isn't editable or 404s, fall back to listing versions / creating one as usual.
3. `PATCH /v1/appStoreVersionLocalizations/{en-US id}` with `description`, `promotionalText`, `keywords` parsed from `AppStore/metadata.md` (metadata.md stays canonical — parse its sections rather than duplicating strings in the script).
   **whatsNew**: ASC rejects `whatsNew` on an app's very first version. Attempt the PATCH including it; on a 409 mentioning whatsNew, retry without and log that it was skipped.
   **Gotcha from the last session**: Apple rejects Tibetan script characters in en-US fields — metadata.md's description already carries a note about this; keep the romanized-only rule when editing copy.
4. Subtitle only if it changed (currently it doesn't): `PATCH /v1/appInfoLocalizations/72bd73bc-...` with `subtitle`.
5. `--dry-run` flag (default ON): GET current values and print current-vs-new for each field, then exit without writing. Run dry first, show the user the diff in chat, and only run with `--apply` after the user confirms — this mutates the listing draft.

**Implementer note:** treat updating the ASC listing as an outward-facing change: show the dry-run diff and get an explicit go-ahead in chat before `--apply`, even though the user requested the update in general terms.

### 5c. What remains manual for the user (list at the end of the final report)

Screenshots (6.7" + 6.5" sets), age-rating questionnaire, pricing/availability, App Privacy answers, and the final "Add for Review"/Submit click — none of these are safely scriptable; the user does them in ASC. Also: a new TestFlight build must be pushed (CI does that on push to main) and attached to the 1.0 version in ASC before submitting.

---

## Commit / verification order

1. §1 + §2 + §3 (Swift logic) — build after each; §2 changes the `ProfileDetailContext` signature, so compile errors will point at any missed call site.
2. §4a/4b (colors) — build; then `xcodegen generate` is NOT needed for asset-only edits, but IS needed after adding `Brand.swift` and the new colorset is picked up automatically (it's inside the existing .xcassets).
3. §4c (icon/logo script + generated assets) — run script, Read both PNGs to visually verify, build.
4. §5a (metadata.md) — commit with the rest.
5. §5b — dry-run, show user, apply on confirmation. The script lives in `ci/` and is committed; the venv is not.
6. Final build + push to main (CI builds the new TestFlight build with the new icon). Per session rules, ask before pushing if the user hasn't already said to.

## QA script (simulator ok for everything except push)

1. Discover: tap the TOP of a card (photo area, center) → expands. Tap left/right thirds → photos page. Single-photo card: tap anywhere → expands.
2. Likes: someone who liked you AND you liked back (matched) appears in NEITHER tab; they're in Chats. "You liked" profile has NO Like back button. "Liked you" profile has a full-width red "Like back"; after tapping it on a mutual like, the bar flips to a full-width blue "Send message" and the match alert offers "Say hi".
3. Colors: chat bubbles/badges/prominent buttons are Facebook blue; all hearts and the LIKE stamp are YouTube red; the PASS X and stamp are blue; nothing pink/green/maroon remains anywhere (flip dark mode too).
4. Sign-in screen shows the new full-color logo (blue handshake + red heart); home screen shows the new icon.
5. ASC: after `--apply`, the 1.0 version's description/promotional text in App Store Connect match metadata.md.
