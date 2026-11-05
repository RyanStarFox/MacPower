---
name: macpower-release
description: >-
  Ship a MacPower release to GitHub, Gitee, Aliyun Drive, Baidu Netdisk, and the
  personal Homebrew tap. Use when the user asks to publish, ship, upload, or
  push a MacPower version, create a GitHub or Gitee release, upload the DMG or
  zip, sync 阿里云盘 or 百度网盘, or bump the Homebrew cask. Also use when they
  ask to repeat the last MacPower release steps.
---

# MacPower release

Publish only when the user asks, and only at the version they name. A release includes the personal Homebrew tap. Official `homebrew/cask` waits for Developer ID and notarization.

Hard rule: a release upload must leave the installed app alone. Do not ditto, copy, or replace `/Applications/MacPower.app`. Do not rewrite its `CFBundleShortVersionString` or `CFBundleVersion`. Do not relaunch it after `gh release` or `sync_latest_release.py`. `make_dmg.sh` only writes `dist/`. Installing a build is allowed only when the user asks to try a local change, and that step is outside this workflow.

Repo: `RyanStarFox/MacPower` on GitHub. Gitee remote name is `gitee` (`Ryan_LS_Wang/MacPower`). Never force-push `main`. Never print tokens from `~/.netrc` or `~/.config/macpower/baidu.json`.

## Version files

- `MacPower/Info.plist`: `CFBundleShortVersionString`, and `CFBundleVersion` one higher than the last shipped build.
- `scripts/make_dmg.sh`: default `${1:-VERSION}`.
- Replace `MacPower/ReleaseNotes.json` with this version only. Eleven languages: `zh-Hans`, `zh-Hant`, `en`, `ja`, `ko`, `fr`, `de`, `es`, `pt-BR`, `it`, `ru`. Each value is bullet lines starting with `•`, separated by `\n`. Do not pretty-print `Localizable.xcstrings`. Do not commit `scripts/__pycache__` or `dist/`.

Commit message style: `Ship 2.1.0 with headphone battery rings.` Then `git push origin HEAD`.

In `docs/todo.md`, rename the heading `### 下一个版本` to `### VERSION` and keep the items under it. Above that heading, add a new empty `### 下一个版本` followed by `目前没有。` Include this file in the release commit.

## GitHub Release

Do not create a local annotated tag before `gh release create`. Build first:

```bash
./scripts/make_dmg.sh VERSION
```

That Release-builds into `dist/DerivedData`, ad-hoc signs with `MacPower/MacPower.entitlements --options runtime --timestamp=none`, and writes `dist/MacPower-VERSION.dmg` and `.zip`. It does not install to `/Applications`; do not install or relaunch afterward either. Do not start a second `xcodebuild` while one is running. Apple Development signatures look damaged on other Macs, so the public files stay ad-hoc.

`gh release create vVERSION --repo RyanStarFox/MacPower` with the dmg and zip attached. The body has a short human summary, then the notes JSON and the zip sha256. `make_dmg.sh` prints the sha256.

```html
<!-- macpower-notes
{"zh-Hans":"…","en":"…"}
-->
<!-- macpower-sha256
64 lowercase hex of the zip
-->
```

The notes JSON is the contents of `ReleaseNotes.json` on one line. The in-app updater refuses a zip whose sha256 does not match.

To replace a tag: `git tag -d vVERSION`, `gh release delete vVERSION --repo RyanStarFox/MacPower --yes --cleanup-tag`, `git push gitee :refs/tags/vVERSION`, then create the release again. Do not delete the remote tag until the user wants that tag replaced.

## Mirrors

After the GitHub Release exists:

```bash
python3 scripts/sync_latest_release.py
```

It reads the latest GitHub release, pushes `origin/main` and the tag to `gitee`, uploads the dmg and zip to the Gitee release, Aliyun `/软件/MacPower`, and Baidu via `scripts/upload_baidu.py`. State is `~/.config/macpower/synced.json`. If that state already equals the tag, the script prints `已同步` and returns. Aliyun `--skip` and the Gitee "already attached" check will not replace a same-name file; delete the old file or rerun the Aliyun upload with overwrite when replacing bytes under the same name. A rotated Baidu refresh token is written back to `~/.config/macpower/baidu.json`. The Gitee token stays in `~/.netrc` under `machine gitee.com`. Do not print it, and do not commit it.

## Homebrew cask

After the GitHub Release exists, update the personal tap `RyanStarFox/homebrew-tap` from a local checkout of that repository. The cask is `Casks/macpower.rb`.

- Set `version` to this version.
- Set `sha256` to the checksum of `dist/MacPower-VERSION.dmg`. That is the dmg, not the zip. Confirm the same checksum on the GitHub release asset before pushing.
- Leave `depends_on macos: :sonoma`. Do not add `depends_on arch: :arm64`. The app is a universal binary.
- Keep the ad-hoc comment and the `--no-quarantine` install command.
- Run `brew style` on `Casks/macpower.rb`.
- Commit with `Update MacPower cask to VERSION.` and `git push origin HEAD`. Never force-push. If the push is rejected, fetch and merge, then keep this version and this dmg checksum.
