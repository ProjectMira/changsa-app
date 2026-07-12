# CI code signing

TestFlight archives are signed with one fixed **"Apple Distribution: Tashi
Tsering"** certificate (id `66BLRC6UF8`, expires 2027-07-12) and matching
**"Drokpo App Store CI"** provisioning profile (id `PJ43SYDBX8`), instead of
Xcode's Automatic signing.

## Why

GitHub's macOS runners are wiped clean after every job. Automatic signing
needs the *private key* half of a certificate to sign anything, and that key
only ever existed in the previous runner's now-deleted keychain — so on a
fresh runner, Xcode's only option is to mint a **brand new** "Apple
Development" certificate every single run. Apple caps how many of those an
account can hold at once, so this eventually fails with "Choose a
certificate to revoke. Your account has reached the maximum number of
certificates."

Manual signing with one certificate stored as a secret and reused every run
avoids this entirely — no new certificate is ever created by CI.

## How it's wired

- [project.yml](../project.yml): `Debug` config stays `CODE_SIGN_STYLE:
  Automatic` (simulator/local dev, unaffected). `Release` config (used by
  `xcodebuild archive`, which defaults to Release) is `Manual`, pinned to
  `CODE_SIGN_IDENTITY: "Apple Distribution"` /
  `PROVISIONING_PROFILE_SPECIFIER: "Drokpo App Store CI"`.
- [exportOptions.plist](exportOptions.plist): `signingStyle: manual` with an
  explicit `provisioningProfiles` mapping, so the export/upload step doesn't
  fall back to automatic management either.
- [testflight.yml](../.github/workflows/testflight.yml) "Import signing
  certificate and provisioning profile" step: decodes the secrets below into
  a fresh temporary keychain, adds Apple's WWDR G3 intermediate certificate
  (required to build the trust chain — without it, signing fails with
  `errSecInternalComponent` / "unable to build chain to self-signed root"),
  and installs the profile. The keychain is deleted at the end of the job.

## Repo secrets

| Secret | Contents |
|---|---|
| `BUILD_CERTIFICATE_P12` | base64 of the certificate + private key, PKCS#12 |
| `BUILD_CERTIFICATE_PASSWORD` | password the `.p12` was exported with |
| `BUILD_PROVISIONING_PROFILE` | base64 of the `.mobileprovision` |

## Rotating before the 2027-07-12 expiry

1. Generate a new CSR and create a certificate via the ASC API
   (`POST /v1/certificates`, `certificateType: DISTRIBUTION`) or in
   [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list).
2. Export it with its private key as a `.p12`.
3. Create a new App Store profile bound to it (`POST /v1/profiles`,
   `profileType: IOS_APP_STORE`, bundle id `app.drokpo.ios`) or via the
   portal, named "Drokpo App Store CI" (or update
   `PROVISIONING_PROFILE_SPECIFIER` / `exportOptions.plist` if renamed).
4. Update the three GitHub Actions secrets above with the new values.
5. Revoke the old certificate once the new one is confirmed working.
