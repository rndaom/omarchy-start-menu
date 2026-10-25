# Start menu for Omarchy

A Windows-style start menu for Omarchy's floating workspaces, drawn in your Omarchy theme. It opens from the dock's apps button and from a tap of the Super key, and hangs from the button the way a start menu sits on its taskbar.

- **Search** at the top: just start typing. The best match is first; `Enter` opens it.
- **Pinned** apps in a grid. Drag one onto another to swap places, or right-click for _Move to front_. Until you pin something here, it shows the apps you keep in the dock.
- **Recent** apps you opened from the menu, with how long ago.
- **All apps**, A to Z. Click a letter to jump to another one.
- **Footer**: your picture, Files, the Omarchy menu, and a power button with Lock, Sleep, Log out, Restart and Shut down. Click the picture to choose one (the desktop's file chooser opens) or to remove it; without one it shows your initial in the theme's accent colour.
- **Right-click** any app to open it, pin or unpin it, keep it in the dock, take it off Recent, or uninstall it.

Keyboard: arrows move, `Enter` opens, `Tab` switches between the home view and All apps, `Menu` or `Shift + F10` opens the selected app's menu, `Delete` uninstalls, and `Escape` steps back: it clears the search, leaves All apps, then closes the menu.

Like Omarchy's other launchers it opens and closes without animating, since one key summons it many times a day.

## Install

```bash
omarchy plugin add https://github.com/rndaom/omarchy-start-menu.git --enable
```

Then hand it the dock's apps button:

```bash
omarchy dock launcher rndaom.start-menu
```

`omarchy dock launcher grid` puts the app grid back. The apps button, `Super + Alt + Space`, and a tap of Super on a floating workspace then open the start menu.

### Before your Omarchy has `omarchy dock launcher`

Handing the dock's button to a plugin needs a dock change that is on its way into Omarchy. Until your Omarchy has it, the dock's button keeps opening the app grid, and you can open the start menu with a tap of Super by adding this to `~/.config/hypr/bindings.lua`:

```lua
-- Start menu on a tap of Super, on floating workspaces. Remove once Omarchy
-- ships `omarchy dock launcher`, which binds the tap itself.
local function start_menu()
  local workspace = hl.get_active_workspace()
  if workspace then
    -- Hyprland reads a command that starts with `[` as window rules, hence
    -- the `if` around the test.
    hl.exec_cmd("if [[ $(omarchy-hyprland-workspace-layout-current " .. workspace.id .. ") == floating ]]; then"
      .. " omarchy-shell shell toggle rndaom.start-menu \"{\\\"position\\\":\\\"$(omarchy-dock position)\\\"}\"; fi")
  end
end
o.bind_commands[start_menu] = "omarchy-shell shell toggle rndaom.start-menu"
o.bind("SUPER + Super_L", "Start menu", start_menu, { release = true })
o.bind("SUPER + Super_R", "Start menu", start_menu, { release = true })
```

Without the dock's help the menu sits centered above the dock's edge rather than on its button.

## Where it keeps things

- Pins: `~/.config/omarchy/start-menu.json`
- Your picture: `~/.face`, the usual place for it on Linux, which login screens read too. Removing it from the menu moves it to the trash.
- Recent apps: `~/.local/state/omarchy/start-menu/recent.json`

## Development

`StartMenuModel.js` holds the logic that needs no Quickshell (pins, recent apps, letters, placement, arrow keys); `node test/model.test.js` tests it. The menu itself is `StartMenu.qml`, a `menu` plugin that receives the dock's launcher payload in `open(payloadJson)`:

```json
{ "screen": "DP-1", "position": "bottom", "dock": { "x": 812, "y": 1328, "width": 936, "height": 64 }, "button": { "x": 812, "y": 1328, "width": 64, "height": 64 } }
```
