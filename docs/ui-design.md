# UI design

The configuration UI (`sync.bat --config`) is built with **WPF + XAML**, hosted by PowerShell. The visual language follows [`DESIGN.md`](../DESIGN.md), which is an Anthropic / Claude.com–inspired styleguide.

## Branding casing

- **Display brand:** `GitHerd` (capital H). Used in the window title, the inline header wordmark, and prose.
- **Filename / CLI brand:** `githerd` (all lowercase). Used for the repository name, folder, and any path-like reference.

## Files

| File | Role |
|---|---|
| [`ui/config-ui.ps1`](../ui/config-ui.ps1) | Host script. Loads the XAML, wires events, validates and writes `config.json`, returns the exit code `sync.bat` keys off. |
| [`ui/MainWindow.xaml`](../ui/MainWindow.xaml) | Window layout: header → optional error banner → project list + detail editor → post-sync command card → footer buttons. |
| [`ui/Theme.xaml`](../ui/Theme.xaml) | Resource dictionary holding all design tokens (colors, radii, typography) plus templated styles for buttons, text boxes, list boxes, and the card containers. |

`Theme.xaml` is merged into the window's resources at runtime (`Window.Resources.MergedDictionaries.Add(theme)`). `MainWindow.xaml` therefore uses **`DynamicResource`** lookups, not `StaticResource`, so styles resolve after the merge.

## DESIGN.md → WPF mapping

| DESIGN.md token | WPF resource | Value |
|---|---|---|
| `colors.canvas` | `Canvas` | `#FAF9F5` |
| `colors.surface-card` | `SurfaceCard` | `#EFE9DE` |
| `colors.ink` | `Ink` | `#141413` |
| `colors.muted` | `Muted` | `#5A544A` |
| `colors.hairline` | `Hairline` / `HairlineStrong` | `#E6DFD8` / `#D8CFC2` |
| `colors.primary` | `Primary` | `#CC785C` (coral) |
| `colors.primary-active` | `PrimaryActive` | `#A9583E` |
| `rounded.md` | `RadiusInput` | `8` (inputs, buttons) |
| `rounded.lg` | `RadiusCard` | `12` (cards) |
| `text-input` | `TextBoxStyle` | 1px hairline → 1.5px coral on focus + 3px coral-washed outer ring |
| `button-primary` | `PrimaryButton` | Coral fill, white text, darkens on hover/press |
| `button-secondary` | `SecondaryButton` / `SecondaryButtonSmall` | Cream fill, hairline border, coral border on hover |
| `feature-card` | `Card` style on `Border` | Surface-card background, hairline border, 12px radius |
| `badge-pill` | `BadgePill` / `BadgePillCoral` | Squarer chip badges (5px corner radius) with surface-card or coral-washed fill, used for the per-project remote, branch, and merge-mode indicators in the list |

## Font substitutions

Real **Copernicus** (display serif) and **StyreneB** (UI sans) are licensed and not installed on Windows. The theme uses widely-available fallbacks instead:

| Role | DESIGN.md | Used here |
|---|---|---|
| Display headlines | Copernicus | **Cambria** (serif) |
| Body text | StyreneB | **Segoe UI** (sans) |
| Code / mono | JetBrains Mono | **Consolas** |

If you have the licensed fonts installed, edit the `FontDisplay` / `FontBody` resources at the top of `Theme.xaml`.

## List + detail pattern (why no DataGridView)

The previous WinForms UI used a `DataGridView`. That control's cell-editor needs a double-click or F2 to enter edit mode, drops edits when focus shifts, and treats checkboxes awkwardly. The new UI is a **list + detail form**:

* Left card — a `ListBox` of projects rendered as cards with name, path,
  Development repo, Master repo, branch, and `merge` / `pull only` badges.
* Right card — text fields plus themed **Development repo**, **Master repo**,
  and **Master branch** `ComboBox` controls and a separate merge `CheckBox`.
  Edits push back to the list-bound view-model as they change.

Remote options come from `git remote -v`; Development repo display prefers the
push URL and Master repo display prefers the fetch URL. Branch options come
from `git branch --format=%(refname:short)`. If discovery is unavailable,
selectors retain saved values and add their schema fallbacks, keeping imported
and temporarily unavailable projects editable without treating discovery as
validation.

The detail pane and project list use narrow, rounded scroll thumbs instead
of the default Windows scrollbar chrome. The remote dropdown uses the same
cream surface, coral focus ring, rounded corners, and hover states as the
existing text inputs.

`+ Add project` adds a new entry that shows *Untitled project* in italic muted text until you give it a name. `Remove` drops the selected project. Validation surfaces in a coral-tinted banner at the top of the window — never a `MessageBox` popup.

## Post-sync command field

`final_command` is **single line** by design: `lib/load-config.ps1` writes it as a `set "FINAL_COMMAND=…"` line in the generated batch script, and an embedded newline would break the `set` statement.

The input box (`TxtFinal`) is therefore a single-line `TextBox` with `AcceptsReturn="False"` and `TextWrapping="Wrap"` — long commands wrap visually so you can read them, but pressing Enter is a no-op. The field uses the monospace font so command syntax stays legible.

## Sharing your config (Import / Export)

The header of the window has **↑ Import** and **↓ Export** buttons (`BtnImport`, `BtnExport`) that round-trip the full config — `repos[]`, `final_command`, `max_wait_seconds` — through a plain `.json` file. They sit in the page header (not the *Projects* card) because they act on the whole config, not just the project list. The on-disk shape is identical to `config.json`, so any exported file is also a valid drop-in replacement for it.

- **Export** runs `Validate-And-Build` first, so an exported file is guaranteed to be a valid config (the same checks `Save` runs). Default filename: `githerd-config.json`, default folder: the user's Documents.
- **Import** parses the JSON, sanity-checks that a `repos` array exists, and confirms before replacing a non-empty list. Loaded data goes through the shared `Set-StateFromConfig` helper that also handles initial load, so defaults / clamping (timeout 10–86400) are applied identically.
- Imported state is **not auto-saved** — it sits in the editor so the user can fix machine-specific paths first. After import, GitHerd does a `Test-Path` on every project path and surfaces missing ones in the banner (truncated at five names + "+N more"). Successful import with no missing paths shows `Imported from <file>`.

The banner doubles as an info channel: `Show-Info` reuses `ErrorBox` but swaps `ErrorText.Foreground` from `Danger` to `Ink` so success messages don't read as errors.

## Exit-code contract (unchanged)

| Code | Meaning |
|---|---|
| `0` | Saved and closed |
| `10` | Saved with **Save & Run** — `sync.bat` immediately runs the sync |
| `2` | Cancelled — `sync.bat` exits without running |
| `1` | Error |

Don't change this without also updating the dispatch in `sync.bat`.
