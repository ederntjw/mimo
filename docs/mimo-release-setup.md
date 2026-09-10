# Mimo releases from GitHub

Public Mimo downloads need Developer ID signing and Apple notarization. An app
that launches on the developer's Mac has not necessarily passed the checks that
apply to a browser download on another Mac. Apple's [distribution
guidance](https://developer.apple.com/developer-id/) explains the signing and
notarization process.

## Apple signing setup

1. Use an Apple Developer Program team with a **Developer ID Application**
   certificate. Apple Development is for development; Apple Distribution is for
   App Store distribution. Developer ID Installer is for installer packages, not
   this app-and-DMG distribution. See Apple's [certificate
   types](https://developer.apple.com/help/account/certificates/certificates-overview).
2. If the team does not have the certificate, its Account Holder can create it
   through Certificates, Identifiers & Profiles. Apple's [Developer ID
   instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
   describe certificate creation and the separate cloud-managed certificate
   access available to authorized admins.
3. The build machine needs the certificate **and its matching private key**.
   Export the signing identity from Keychain Access as a password-protected
   `.p12`. Downloading a `.cer` alone does not provide the private key. Keep the
   original identity backed up securely and limit access to the release team.
4. Configure Apple notarization credentials for the same team: Apple Account,
   app-specific password, and Team ID. The workflow imports them into a temporary
   keychain profile and uses `notarytool`.

The release app and its executable helpers need valid signatures, a secure
timestamp, and the hardened runtime. Distribution entitlements must not enable
`com.apple.security.get-task-allow`. The notary service reports signing problems
in its submission log; see Apple's [notarization
troubleshooting](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

## GitHub configuration

Configure these in the repository's **Settings → Secrets and variables →
Actions**. Store secret values there, never in source files or release notes.

| Kind | Name | Value |
| --- | --- | --- |
| Variable | `MIMO_DEVELOPER_ID` | Exact `Developer ID Application: … (TEAMID)` signing identity name |
| Optional variable | `MIMO_SUPABASE_URL` | Mimo Account HTTPS project URL; configure together with the publishable key |
| Optional variable | `MIMO_SUPABASE_PUBLISHABLE_KEY` | Supabase client publishable key; configure together with the project URL |
| Secret | `MIMO_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 encoding of the exported `.p12` identity |
| Secret | `MIMO_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used to encrypt that `.p12` |
| Secret | `MIMO_NOTARY_APPLE_ID` | Apple Account used for notarization |
| Secret | `MIMO_NOTARY_APP_PASSWORD` | Its app-specific password |
| Secret | `MIMO_NOTARY_TEAM_ID` | Developer Program Team ID |
| Secret | `MIMO_SPARKLE_PRIVATE_KEY` | Existing Mimo Sparkle EdDSA private key matching the public key shipped in the app |

Mimo Account sync is optional. Leave both Supabase variables absent to keep the
library on this Mac; meeting recording, transcription, and summaries remain
available. The release configuration check rejects an incomplete pair or an
invalid HTTPS project URL. It does not contact an account server. A build without
these settings explains that account sync is unavailable and does not require
an account during onboarding.

Developer ID establishes macOS trust; the Sparkle key authenticates updates to
already-installed copies of Mimo. Keep both identities stable. A new Sparkle key
must not be substituted without an update-key migration plan.

## Recovering an interrupted notarization

`scripts/build_mimo_dmg.sh` uploads each artifact once, saves the submission ID,
then waits up to 20 minutes. A wait timeout does not cancel Apple's processing.
After notarization starts, a failure or cancellation retains the exact signed
artifacts under the printed `.mimo-package.*` directory. Its `notarization/app`
and `notarization/dmg` directories keep separate upload and wait responses,
stderr, exit codes, submission logs when available, and the submitted file's
SHA256. An `upload-completed.txt` marker means the upload command succeeded.
Successful packaging removes this temporary directory.

Signing and notarization staging use the private temporary directory
(`${TMPDIR:-/tmp}`), independently of the DMG output folder. Set
`MIMO_PACKAGE_WORK_ROOT` to an absolute local directory to override it. Keep that
directory outside cloud-synced Documents/Desktop folders: File Provider can
reattach Finder metadata to nested app bundles while they are being signed.
Only the finished, verified DMG is copied into the output folder. Its copied
bytes must match before it is exposed atomically, including when staging and
output are on different volumes.

Use the printed `notarytool info`, `wait`, and `log` commands with the saved ID.
If a confirmed upload remains `In Progress`, continue waiting on that ID; do not
upload the same build again merely because the wait timed out. An ID or
`In Progress` status without confirmed upload completion is ambiguous: Apple
can also show that status for an incomplete upload. Inspect the upload receipts
before deciding to retry. See [Apple's explanation of incomplete
uploads](https://developer.apple.com/forums/thread/829204?answerId=896809022).

For a diagnosed local upload-route problem, set
`MIMO_NOTARY_S3_ACCELERATION=0` on the next deliberate submission to disable S3
Transfer Acceleration; the default remains `1`. The script never automatically
resubmits. Recovery is manual: acceptance still requires stapling, signature and
Gatekeeper checks, and verification of the app inside the final DMG. Do not
publish an artifact directly from retained staging. Retained directories on a
temporary CI runner need to be recovered before that runner is discarded.

## Release verification

Use `.github/workflows/mimo-release.yml` for public Mimo releases. Release source,
tag, version, and release notes must refer to the same commit. The publication
gate should retain a draft until its uploaded assets have been downloaded and
verified against the final local artifacts.

The required order is: sign the app, notarize and staple the app, create and sign
the DMG from that app, notarize and staple the DMG, then generate the Sparkle
signature and checksum for those final DMG bytes. Do not modify an artifact after
signing its Sparkle update metadata. Verify the downloaded DMG and appcast bytes
before publishing the release or moving the latest update feed.

For the downloaded DMG, verify both its signature and staple. Mount it and verify
the embedded app's signature, staple, and distribution assessment. On macOS 14
or later, Apple's recommended app assessment is:

```bash
syspolicy_check distribution /path/to/Mimo.app
xcrun stapler validate /path/to/Mimo.app
spctl -a -t open -vvv --context context:primary-signature /path/to/Mimo.dmg
xcrun stapler validate /path/to/Mimo.dmg
```

Each command must succeed. A notarization submission marked `Accepted` is useful
evidence, but Gatekeeper applies additional checks. The strongest final test is a
fresh Mac or restored virtual machine: download with Safari, disconnect from the
network, then install and launch normally. This preserves download quarantine
and checks that stapled tickets work without contacting Apple. Command-line
downloads alone do not reproduce that first-launch experience. See Apple's
[Testing a Notarised Product](https://developer.apple.com/forums/thread/130560)
and [trusted execution
diagnostics](https://developer.apple.com/forums/thread/706442).

A normal first-launch confirmation may still appear for a notarized app. A
warning that Apple cannot verify the developer or check the app for malicious
software means the public release path needs investigation. Preview or ad-hoc
builds must not be advertised as ready for normal public installation. Since
macOS Sequoia, Control-click → Open no longer overrides signing or notarization
failures; Apple documents this [runtime protection
change](https://developer.apple.com/news/?id=saqachfa).
