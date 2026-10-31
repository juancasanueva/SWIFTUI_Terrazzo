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
| `run/state.json` | Workspaces for the command line, written by the app. Numbers, monitor positions and app names |
| `layout.json` | Where windows are, written by the app so a restart can put them back. Window numbers and app identifiers only, never titles |

The app writes these when you change something in its interface, and reloads them within a moment when you edit them by hand. Keys you leave out take their default. If a file can't be parsed, the app keeps its last good values, tells you which file has the error, and refuses to overwrite it until you fix it.

```json
{ "gap": 12, "layout": "side", "mainSize": "twoThirds", "windowsPerScreen": 4 }
```

The active window border follows `highlight.cornerRadius`, in points: 16 by default, which is what standard macOS windows measure. Apps that draw their own corners may need another value; it's also in Settings → Highlight.

The pointer follows focus, like AeroSpace's `move-mouse`. `movePointer.onWindowFocus` sends it to the center of the focused window when it isn't already over it, and `movePointer.onMonitorChange` sends it to a monitor's center when focus lands on another one, as with an empty workspace. Both are on by default, and they're also in Settings → Highlight.

```json
{ "movePointer": { "onWindowFocus": true, "onMonitorChange": true } }
```

The bars above stacked windows have their own settings: `color` as hex, and `hoverDelay`, the seconds the pointer rests on a bar before the panel with the window icons opens, from 0 to 10. Both are also in Settings → Highlight.

```json
{ "stackBar": { "color": "#3B82F6", "hoverDelay": 2.5 } }
```

Shortcuts use `ctrl`, `opt`, `shift` and `cmd` joined with `+`; the word `off` disables one. Action names are the case names of `ShortcutAction` in `tiling/Domain/Shortcuts.swift`.

```json
{ "prefix": "ctrl+opt", "bindings": { "retile": "ctrl+opt+t", "noPeek": "off" } }
```

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌃ ←→↑↓ | Focus the window in that direction, or the next screen. macOS uses these keys for Mission Control and Spaces by default; turn those off in System Settings → Keyboard → Keyboard Shortcuts → Mission Control |
| ⌃⇧ ←→↑↓ | Swap with the neighbor, or move to the next screen |
| ⌃ 1–9 | Switch to that workspace |
| ⌃⇧ 1–9 | Move the active window to that workspace |
| ⌃⌥↩ | Make the active window primary |
| ⌃⌥] ⌃⌥[ | Activate next / previous window |
| ⌃N ⌃⇧N | Next / previous window in this tile |
| ⌥⇥ ⌥⇧⇥ | Tab View |
| ⌃⌥ ←→↑↓ | Resize: move the window's edge that way. The edge on that side if it has a neighbor there, otherwise the opposite edge, so the window shrinks. Each press moves `resizeStep` percent of the screen: 5 by default, from 0.5 to 25, in `settings.json` or Settings → Layout |
| ⌃⌥0 | Reset sizes |
| ⌃T | Float the active window, or tile it again |
| ⌃⌥⇧F | Always float this app |
| ⌃F | Focus mode |
| ⌃⌥D | No peek mode |
| ⌃⌥P | Clean Space |
| ⌃⌥R | Retile |
| ⌃⌥⌘1–5 | Windows on this screen |

⌘-drag a window to swap, ⌥⌘-drag to add it to a stack, drag to another screen to move it, and drag a shared edge to resize.

## Workspaces

There are nine numbered workspaces, separate from macOS Spaces, working like AeroSpace's: each display shows one, and a workspace not showing keeps its windows parked in a corner of the screen. Pressing a number goes to that workspace wherever it is. Floating and excluded apps' windows stay visible on every workspace. Parked windows come back when the app quits or tiling is paused, and return to their workspace on the next launch.

## Restarts

Restarting the app puts windows back: tiles, stacks, floats, and each window's workspace. macOS gives a window a new number when it is reopened, so windows are not remembered across quitting their app or restarting the Mac. Focus mode and Clean Space end with the app.

To keep workspaces on particular monitors, map numbers to part of a monitor's name in `settings.json`, or use Settings → Layout → Workspace displays. A workspace always shows on its monitor while that monitor is connected, and otherwise comes to the focused one.

```json
{ "workspaceDisplays": { "1": "LG", "2": "LG", "7": "Odyssey", "8": "Odyssey" } }
```

## Command line

The app's binary answers questions and takes commands, so bars such as SketchyBar can show workspaces. Arguments follow AeroSpace's where they overlap, so scripts written for it only need to call a different program.

```sh
tiling list-workspaces --all
tiling list-workspaces --focused
tiling list-workspaces --monitor all --format '%{workspace} %{monitor-appkit-nsscreen-screens-id}'
tiling list-windows --workspace 3 --format '%{app-name}'
tiling workspace 3
```

To be told when workspaces change, set a program and arguments in `settings.json`. It runs directly, without a shell, and `{workspace}` becomes the focused number:

```json
{ "onWorkspaceChange": ["/opt/homebrew/bin/sketchybar", "--trigger", "aerospace_workspace_change", "FOCUSED_WORKSPACE={workspace}"] }
```

Windows that float, and apps excluded from tiling, belong to no workspace and aren't listed.

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
