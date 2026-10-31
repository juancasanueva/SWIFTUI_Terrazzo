# Tiling

A macOS tiling window manager, modelled on the behavior of [the reference app]: windows take a place when they open, the rest reflow when one closes, and extra windows stack in the tile you're using. Requires macOS 15 or later and Accessibility access. It is not sandboxed, because Accessibility control of other apps' windows does not work in the sandbox.

## Config files

Everything lives in plain JSON in `~/.config/tiling/` (or `$XDG_CONFIG_HOME/tiling/`):

| File | Holds |
| --- | --- |
| `settings.json` | Layout defaults, spacing, screen edges, highlight, No peek, Clean Space background, appearance, language, login item |
| `shortcuts.json` | Prefix, master switch, and the shortcuts you changed |
| `apps.json` | Apps that are never tiled, and the minimum sizes learned per app |
| `screens.json` | Layout, window count and dragged sizes per screen and Space |

The app writes these when you change something in its interface, and reloads them within a moment when you edit them by hand. Keys you leave out take their default. If a file can't be parsed, the app keeps its last good values, tells you which file has the error, and refuses to overwrite it until you fix it.

```json
{ "gap": 12, "layout": "side", "mainSize": "twoThirds", "windowsPerScreen": 4 }
```

Shortcuts use `ctrl`, `opt`, `shift` and `cmd` joined with `+`; the word `off` disables one. Action names are the case names of `ShortcutAction` in `tiling/Domain/Shortcuts.swift`.

```json
{ "prefix": "ctrl+opt", "bindings": { "retile": "ctrl+opt+t", "noPeek": "off" } }
```

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌥ ←→↑↓ | Focus the window in that direction, or the next screen. Takes over word navigation in text fields; rebind it if you need that |
| ⌥⇧ ←→↑↓ | Swap with the neighbor, or move to the next screen. Takes over selecting by word in text fields |
| ⌥ 1–9 | Switch to that workspace |
| ⌥⇧ 1–9 | Move the active window to that workspace |
| ⌃⌥↩ | Make the active window primary |
| ⌃⌥] ⌃⌥[ | Activate next / previous window |
| ⌃⌥\` ⌃⌥⇧\` | Next / previous window in this tile |
| ⌥⇥ ⌥⇧⇥ | Tab View |
| ⌃⌥= ⌃⌥- ⌃⌥0 | Bigger / smaller / reset sizes |
| ⌃⌥F ⌃⌥⇧F | Float / always float this app |
| ⌃⌥Z | Focus mode |
| ⌃⌥D | No peek mode |
| ⌃⌥P | Clean Space |
| ⌃⌥R | Retile |
| ⌃⌥⌘1–5 | Windows on this screen |

⌘-drag a window to swap, ⌥⌘-drag to add it to a stack, drag to another screen to move it, and drag a shared edge to resize.

## Workspaces

There are nine numbered workspaces, separate from macOS Spaces, working like AeroSpace's: each display shows one, and a workspace not showing keeps its windows parked in a corner of the screen. Pressing a number goes to that workspace wherever it is. Floating and excluded apps' windows stay visible on every workspace. Parked windows come back when the app quits or tiling is paused; after a crash they are tiled again on the next launch, on one workspace.

To keep workspaces on particular monitors, map numbers to part of a monitor's name in `settings.json`, or use Settings → Layout → Workspace displays. A workspace always shows on its monitor while that monitor is connected, and otherwise comes to the focused one.

```json
{ "workspaceDisplays": { "1": "LG", "2": "LG", "7": "Odyssey", "8": "Odyssey" } }
```

On layouts where ⌥ + number types a character (⌥2 is `@` on Spanish keyboards), those characters can't be typed while the app runs. Rebind `workspace1`…`workspace9` and `moveToWorkspace1`…`moveToWorkspace9` in `shortcuts.json` if you need them.

## Layout of the code

- `tiling/Domain`: pure layout, workspace state and config logic, covered by unit tests.
- `tiling/Adapters`: Accessibility, displays and Spaces, global hotkeys, config file watching.
- `tiling/App`: the controller that connects the domain to the system, and pointer tracking.
- `tiling/UI`: overlays, menu-bar panel, settings, Tab View and tour.

`_AXUIElementGetWindow` and SkyLight's Space functions are private macOS API with no public equivalent. Space support degrades to one Space if the SkyLight functions disappear.

## Tests

```sh
xcodebuild test -scheme tiling -only-testing:tilingTests -destination 'platform=macOS'
```
