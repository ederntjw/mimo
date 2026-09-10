# Mimo release checklist

Use `.github/workflows/mimo-release.yml` for public releases from
`ederntjw/mimo`. See [release setup and recovery](../docs/mimo-release-setup.md)
for credentials, notarization recovery, and the full verification sequence.

## Before packaging

- [ ] Required tests pass on macOS and the source, version, tag, and release notes agree.
- [ ] Developer ID signing and Apple notarization credentials are configured.
- [ ] The existing Mimo Sparkle update key is used.
- [ ] The complete LocalVQE runtime is available.
- [ ] The app displays **Mimo**, and the installer artwork also says **Mimo**.
- [ ] Original MIT copyright/license and third-party attribution are included.

## Distribution checks

- [ ] `scripts/build_mimo_dmg.sh` builds the app outside cloud-synced folders.
- [ ] The app and all executable helpers have valid Developer ID signatures.
- [ ] The app is accepted by Apple, stapled, and passes distribution assessment.
- [ ] The DMG is created from that exact app, signed, accepted, and stapled.
- [ ] The app inside the final mounted DMG passes signature and notarization checks.
- [ ] Sparkle metadata and checksums describe the final DMG bytes.
- [ ] The draft release's downloaded assets match the verified local files.
- [ ] The publication gate completes before the release becomes public.

Any content change inside the app requires signing and notarizing the resulting
bundle again. Do not remove quarantine attributes to simulate download approval.
Keep existing bundle identifiers, data paths, credential names, and update keys
stable; changing the visible product name does not require renaming these.

## Local replacement

Use `scripts/install_local_app.sh --install-staged /absolute/path/Mimo.app --launch`
to install the verified app. The installer archives the old bundle and preserves
app data. One everyday app lives at `/Applications/Mimo.app`.
