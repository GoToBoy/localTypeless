# CI build pipeline

`.github/workflows/build.yml` runs on every push to `main`, every pull request, and on manual dispatch. The matrix has two flavors mirroring the local make targets:

| Flavor | Runner | Make target (build) | Make target (test) | Artifact |
|---|---|---|---|---|
| `arm64` | `macos-14` | `build-ci` | `test-ci` | `LocalTypeless-arm64.zip` |
| `x86_64` | `macos-15-intel` | `build-portable-ci` | `test-portable-ci` | `LocalTypeless-x86_64.zip` |

Each job: pin Xcode → install xcodegen → import the signing certificate into a temp keychain → build → verify architecture → codesign → zip → upload artifact → run tests (allowed to fail without blocking the artifact).

## Why this shape

- **`-ci` make targets drop `-quiet`** so `xcodebuild` errors actually appear in workflow logs. The local targets keep `-quiet` so the terminal stays readable.
- **Build is unsigned, then signed separately.** `build-ci` passes `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`, so xcodebuild emits a linker-ad-hoc binary that we overwrite via `make sign-ci`. This keeps signing logic out of the Xcode build settings and avoids xcodebuild trying to pick an identity from an empty keychain on first run.
- **Do not trust the self-signed certificate inside CI.** Hosted macOS runners can block on `security add-trusted-cert` waiting for SecurityAgent UI. The workflow only imports the p12 and unlocks codesign access with `security set-key-partition-list`; diagnostics may show `CSSMERR_TP_NOT_TRUSTED`, but the later `make sign-ci` step is the actual signing gate.
- **Tests run after artifact upload, with `continue-on-error`.** A red test job doesn't prevent the build artifact from shipping. Local `make test` remains the pre-merge gate.
- **Xcode is pinned via `maxim-lobanov/setup-xcode@v1` with `latest-stable`** because xcodegen 2.45+ emits pbxproj `objectVersion 77`, which only Xcode 16+ can read. `latest-stable` picks the newest GA Xcode the runner image has installed.

## Signing identity setup (one-time)

CI signs with a self-signed certificate kept in repository secrets. Same identity across every CI run = stable code requirement on the user's machine = TCC grants (Microphone, Accessibility, Input Monitoring) survive across upgrades. Ad-hoc signing would change cdhash on every build and force users to re-grant permissions every release.

**Use a CI-specific identity, not the developer's local `Glossa Local Dev Code Signing`.** Keeping CI and local separate limits blast radius if either keychain leaks.

### 1. Generate the CI identity locally

```sh
scripts/export-ci-signing-identity.sh
```

The script prints four values and leaves the p12 on disk at the path it shows. Output looks like:

```
Paste these values as GitHub repository secrets:

  MACOS_SIGNING_IDENTITY                  = LocalTypeless CI Code Signing
  MACOS_SIGNING_CERTIFICATE_PASSWORD      = <random>
  MACOS_KEYCHAIN_PASSWORD                 = <random>
  MACOS_SIGNING_CERTIFICATE_P12_BASE64    = <base64 blob>
```

### 2. Upload as repository secrets

GitHub → Settings → Secrets and variables → Actions → New repository secret. Add all four.

Once the secrets are saved, delete the working copy on disk — the script prints the exact `rm -rf` command for the temp directory it used (under `$TMPDIR`, which on macOS is `/var/folders/…/T/local-typeless-ci-signing.*`).

### 3. Verify

Push a branch or trigger the workflow manually. The "Import signing certificate" step prints the identity it loaded. The "Sign .app" step shows `codesign --verify` output ending in `satisfies its Designated Requirement`.

If the secrets are missing, the workflow falls back to ad-hoc signing and emits a warning — the artifact still builds, just without persistent TCC behavior.

## User install experience

Until the project is enrolled in the Apple Developer Program ($99/year) and the artifact is notarized via `notarytool`, Gatekeeper will warn users that the app is from an unidentified developer.

First-install procedure for an end user:

1. Download the zip from a GitHub Release, unzip.
2. Drag `LocalTypeless.app` to `/Applications/`.
3. **Right-click the app → Open** (or run `xattr -d com.apple.quarantine /Applications/LocalTypeless.app` once). Confirm the Gatekeeper dialog.
4. Grant Microphone, Accessibility, and Input Monitoring in System Settings → Privacy & Security when the app prompts.

Subsequent releases signed with the same CI certificate will be opened by Gatekeeper without re-prompting (still subject to the quarantine attribute on each fresh download), and TCC will remember permission grants across upgrades.

## Releases

`.github/workflows/release.yml` cuts a public, permanent release from a tag. It triggers on `git push --tags` for any tag matching `v*`, or via manual `workflow_dispatch` (requires typing the version in the dispatch form).

The release job:

1. Resolves the version (strips the leading `v` from the tag, or takes the dispatch input verbatim).
2. Pins Xcode and imports the same signing certificate the `build` workflow uses — release artifacts share the code requirement with regular builds, so users who installed a CI build keep their TCC grants after upgrading to a release.
3. Builds, codesigns, zips with a versioned filename: `LocalTypeless-{version}-{arm64|x86_64}.zip`.
4. Computes a `.sha256` sibling so users can verify the download.
5. Uploads the `.zip` + `.sha256` to a **draft** GitHub Release. Drafts are not visible to the public until you publish them in the GitHub UI — the draft step is the place to add release notes, screenshots, and review the assets before they go live.

Required secrets are the same four the `build` workflow uses. Unlike `build`, the release workflow **fails hard** when secrets are missing — release artifacts must be properly signed, ad-hoc is not acceptable for distribution.

### Cutting a release

```sh
# Bump the version in project.base.yml (CFBundleShortVersionString) and commit.
git tag v0.2.0
git push origin v0.2.0
```

Watch the workflow run in Actions. When it finishes, go to the repo's **Releases** page → the draft release is waiting. Edit the notes, then click **Publish release**.

For a manual one-off (no tag), use the Actions tab → `release` workflow → "Run workflow" → enter the version (without the `v`). The job will create a draft release named `v{version}` — you still need to push the matching git tag separately if you want it to be navigable from the source tree later.

### What the user gets

Public release page on GitHub with two downloadable assets per version:

```
LocalTypeless-0.2.0-arm64.zip       # for M1/M2/M3/M4 Macs
LocalTypeless-0.2.0-arm64.zip.sha256
LocalTypeless-0.2.0-x86_64.zip      # for Intel Macs
LocalTypeless-0.2.0-x86_64.zip.sha256
```

The install flow is the same as in [User install experience](#user-install-experience) — Gatekeeper still warns on the first launch because the cert is self-signed, but TCC grants persist across upgrades because the code requirement is stable.

## Adding notarization later

When the project gets an Apple Developer account:

1. Replace the self-signed cert in CI with a `Developer ID Application` certificate.
2. Add a step after "Sign .app" that runs `xcrun notarytool submit` with credentials from new secrets `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`.
3. Staple with `xcrun stapler staple` before zipping.

The rest of the pipeline (keychain import, `make sign-ci`, artifact upload) stays the same.

## Rotating the CI certificate

Self-signed certificates the script generates are valid for 10 years. If a CI rotation is needed (suspected leak, lost p12), rotate end-to-end:

1. Re-run `scripts/export-ci-signing-identity.sh`.
2. Update all four GitHub secrets.
3. Ship a new release.
4. **Users will need to re-grant TCC permissions** because the code requirement changed. Document this in the release notes.
