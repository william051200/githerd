# Release notes

This page documents the **format** for GitHerd release notes. Use it whenever you cut a new tag.

Release notes live in the **body of the GitHub Release** attached to a Git tag named `vX.Y.Z`. The installer and `githerd --update` both expect that `v`-prefixed semver tag and a `githerd-vX.Y.Z.zip` asset produced by `scripts\build-release.ps1`.

This file is the **template**, not a changelog. Past releases are not duplicated here; read them on the [Releases page](https://github.com/william051200/githerd/releases).

## Template

Copy the block below into the GitHub Release body, then fill it in. Delete any section that doesn't apply — don't leave empty headings behind.

~~~markdown
# GitHerd vX.Y.Z

One short sentence framing what this release is about.

## Highlights

- **Headline feature name.** One- or two-sentence explanation focused on user-visible behavior, not implementation.
- **Second feature.** Same shape — bold lead-in, period, explanation.
- **Third feature.** Cap at 3–5 bullets; longer lists belong in `## What's new`.

## What's new

- **Smaller change.** Same bold-lead-in shape; one fact per bullet.
- **Another change.** Inline code where it helps users recognise the surface (`githerd --update -c`).

## Notes

- Anything an existing user must do by hand (edit `config.json`, re-run `githerd --config`, etc.).
- Caveats, default behavior changes that aren't breaking, env vars to flip a feature on/off.

## Requirements

Windows 10/11, PowerShell 5.1+, Git on PATH.

## Install / Update

If you already have GitHerd:

```
githerd --update
```

Your `config.json` is preserved; a timestamped backup is written to `%LOCALAPPDATA%\GitHerd\config-backups\` just in case.

Fresh install (PowerShell):

```powershell
iex (irm https://raw.githubusercontent.com/william051200/githerd/main/install.ps1)
```

## Verify the download

```
SHA-256: <paste-the-zip-sha256-here>
```

```powershell
(Get-FileHash githerd-vX.Y.Z.zip -Algorithm SHA256).Hash
```
~~~

## Picking sections

Pick exactly **one** of `## Highlights` or `## What's new` (or use both when there's a headline plus incidentals):

| If the release is… | Use |
|---|---|
| First release / big new feature | `## Highlights` only |
| Small / polish / bug-fix | `## What's new` only |
| Mixed (one headline + incidentals) | `## Highlights` then `## What's new` |

`## Notes`, `## Requirements`, and `## Verify the download` are all optional. `v0.3.1` and `v0.3.2` skipped Requirements and Verify entirely — only add them when they tell the user something they couldn't otherwise infer.

## Tagging and publishing checklist

1. Update `VERSION` to `X.Y.Z` (no `v`).
2. Commit and push.
3. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Build the asset: `pwsh -File scripts\build-release.ps1 -Version X.Y.Z`. Note the printed SHA-256 if you plan to include `## Verify the download`.
5. Create the GitHub Release for tag `vX.Y.Z`, paste the filled template, attach `dist\githerd-vX.Y.Z.zip`.
6. Within 24 h, `githerd --update -Check` should report the new version.

## For AI assistants

If you are an AI helping a contributor draft a release, follow these rules so the result matches the existing style without rework:

1. Read the **two most recent** entries on the Releases page first and mirror their tone, bullet phrasing, and section ordering. Style across releases is consistent and intentional — do not invent a new shape.
2. **Do not hard-wrap.** Each bullet is a single line and each prose paragraph is a single line, no matter how long. GitHub Releases renders soft-wrap correctly; hard-wrapping with a 2-space continuation indent makes the body look "cranky" and inconsistent with prior releases.
3. Pick the right top-level "what changed" heading:
   - **`## Highlights`** for first releases or any release with a notable feature push (cf. v0.1.0, v0.2.0, v0.3.0).
   - **`## What's new`** for smaller incremental / polish releases (cf. v0.3.1, v0.3.2).
4. Each bullet under that section starts with a **bold lead-in** naming the feature or change, then a period (or em-dash) and a plain-English explanation. Past tense, third person, no "we" / "this PR".
5. Always include an **`## Install / Update`** section using the exact wording in the template, placed **after `## Requirements`** and before `## Verify the download` — `githerd --update` for upgraders, the one-line `irm | iex` for fresh installs, plus the standard sentence about `config.json` being preserved with a timestamped backup in `%LOCALAPPDATA%\GitHerd\config-backups\`.
6. **Omit sections that don't apply.** Never write "N/A" or "None". `Notes`, `Requirements`, and `Verify the download` are all optional and were dropped in the most recent releases.
7. End the headline area with a single short sentence under the `#` title (one line, no heading) summarising the release's theme. Do not add a `## Summary` heading.
8. Choose the version per [SemVer 2.0.0](https://semver.org/):
   - **MAJOR** — breaking config schema or CLI changes.
   - **MINOR** — new feature, backward compatible.
   - **PATCH** — bug-fix or polish only, backward compatible.
9. Bump `VERSION` (no leading `v`) in the same commit that builds the ZIP, and tag the commit `vX.Y.Z`. The asset attached to the release must be `githerd-vX.Y.Z.zip` from `scripts\build-release.ps1`.
10. No screenshots, no marketing copy, no "thanks for using GitHerd". The body is also read by upgraders skimming `--update` diffs — keep it dense.
