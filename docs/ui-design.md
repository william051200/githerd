# UI design

The configuration UI (`sync.bat --config`) is built with **WPF + XAML**, hosted by PowerShell. The visual language follows [`DESIGN.md`](../DESIGN.md), which is an Anthropic / Claude.com–inspired styleguide.

## Files

| File | Role |
|---|---|
| [`ui/config-ui.ps1`](../ui/config-ui.ps1) | Host script. Loads the XAML, wires events, validates and writes `config.json`, returns the exit code `sync.bat` keys off. |
| [`ui/MainWindow.xaml`](../ui/MainWindow.xaml) | Window layout: header → optional error banner → repo list + detail editor → post-sync command card → footer buttons. |
| [`ui/Theme.xaml`](../ui/Theme.xaml) | Resource dictionary holding all design tokens (colors, radii, typography) plus templated styles for `Button`, `TextBox`, `CheckBox`, `ListBox`, and the card containers. |

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
| `badge-pill` | `BadgePill` / `BadgePillCoral` | Pill border with surface-card or coral-washed fill, used for the per-repo branch + merge-mode indicators in the list |

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

* Left card — a `ListBox` of repos rendered as 3-line cards: name,
  path, and a row of pill badges showing the master branch and an
  `↺ auto-merge` (coral) / `pull only` (muted) indicator. So the merge
  mode is visible at a glance — no need to click into the detail
  panel to know what each repo is configured to do.
* Right card — proper `TextBox` / `CheckBox` controls for the selected
  repo. Edits push back to the list-bound view-model on every keystroke,
  so the list label updates as you type.

`+ Add repository` adds a new entry that shows *Untitled repository* in italic muted text until you give it a name; this avoids the "phantom blank row" feeling and the validator skips fully-empty entries on Save automatically. `Remove` drops the selected repo. Validation surfaces in a coral-tinted banner at the top of the window — never a `MessageBox` popup.

## Exit-code contract (unchanged)

| Code | Meaning |
|---|---|
| `0` | Saved and closed |
| `10` | Saved with **Save & Run** — `sync.bat` immediately runs the sync |
| `2` | Cancelled — `sync.bat` exits without running |
| `1` | Error |

Don't change this without also updating the dispatch in `sync.bat`.
