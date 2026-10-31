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
| ⌃⌥ ←→↑↓ | Swap with the neighbor, or move to the next screen |
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
