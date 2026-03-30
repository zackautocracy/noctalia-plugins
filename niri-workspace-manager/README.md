# Niri Workspace Manager

A workspace management plugin for [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) on the [Niri](https://github.com/YaLTeR/niri) compositor. Save, restore, and organize your workspace layouts across multiple monitors with named profiles.

## Features

- **Layout Profiles**: Create multiple named profiles to save different workspace arrangements. Switch between them on the fly — great for different workflows (e.g. "development", "streaming", "music").
- **Save & Restore**: Capture your current workspace setup (names, order, monitor assignments) and restore it later. Handles creating missing workspaces, reordering, and moving workspaces across outputs automatically.
- **Drag & Drop**: Reorder workspaces within a monitor, or drag them across monitors in the panel. Includes auto-scroll and a floating proxy during cross-output drags.
- **Inline Rename**: Double-click any workspace in the panel to rename it in place. Changes are applied to the compositor immediately.
- **Remove Workspaces**: Remove workspaces directly from the panel — trailing empty workspaces are trimmed automatically.
- **Bar Widget**: Shows the active profile name with an indicator dot when there are unsaved changes compared to the saved layout.
- **Startup Restore**: Optionally restore a specific profile when Noctalia starts, so your workspace layout is always ready.
- **Auto-Assign Windows**: Automatically move windows to their assigned workspaces based on the active profile's saved app assignments.
- **Output Display Names**: Monitor names are auto-detected from hardware info (e.g. "AW3225QF" instead of "DP-2"). Override with custom aliases in settings.
- **Toast Notifications**: Clear feedback for save, restore, profile switch, and error actions.

## Installation

1. Copy the `niri-workspace-manager` folder to `~/.config/noctalia/plugins/`
2. Restart Noctalia Shell
3. Enable the plugin in Settings → Plugins
4. Add the bar widget in Settings → Bar

## Usage

Click the bar widget to open the management panel. From there you can:

- Drag workspaces to reorder or move them between monitors
- Double-click a workspace name to rename it
- Click the trash icon to remove a workspace
- Use the profile dropdown to switch profiles
- Hit the save button to persist your current layout

### Profiles

Profiles store the full workspace layout: workspace names, order, and which monitor they belong to. Each profile also remembers its own window-to-workspace assignments for auto-assign.

The default profile is called "Default". You can create as many profiles as you need — rename or delete them from the panel.

## IPC Commands

All commands use Noctalia's IPC system:

```bash
qs -c noctalia-shell ipc call plugin:niri-workspace-manager <command>
```

| Command | Description |
|---------|-------------|
| `togglePanel` | Toggle the management panel on the current screen |
| `saveLayout` | Save the current workspace layout to the active profile |
| `restoreLayout` | Restore workspaces from the active profile |
| `switchProfile <name>` | Switch to a named profile and restore its layout |
| `nextProfile` | Cycle to the next profile (wraps around) |
| `previousProfile` | Cycle to the previous profile (wraps around) |
| `listProfiles` | Log all profile names (for scripting) |

### Examples

```bash
# Save your current layout
qs -c noctalia-shell ipc call plugin:niri-workspace-manager saveLayout

# Switch to a specific profile
qs -c noctalia-shell ipc call plugin:niri-workspace-manager switchProfile "streaming"

# Cycle through profiles
qs -c noctalia-shell ipc call plugin:niri-workspace-manager nextProfile
```

## Keybinding Examples

### Niri

Add to your niri config (e.g. `~/.config/niri/config.kdl`):

```kdl
binds {
    Mod+Shift+S             { spawn-sh "qs -c noctalia-shell ipc call plugin:niri-workspace-manager saveLayout"; }
    Mod+Shift+BracketRight  { spawn-sh "qs -c noctalia-shell ipc call plugin:niri-workspace-manager nextProfile"; }
    Mod+Shift+BracketLeft   { spawn-sh "qs -c noctalia-shell ipc call plugin:niri-workspace-manager previousProfile"; }
}
```

## Settings

Open Settings → Plugins → Niri Workspace Manager:

| Setting | Default | Description |
|---------|---------|-------------|
| Restore on startup | `true` | Restore the startup profile layout when Noctalia starts |
| Startup profile | `Default` | Which profile to restore on startup |
| Auto-assign windows | `false` | Automatically move windows to their saved workspace assignments |

Output display names can be overridden via the `outputAliases` map in `settings.json`:

```json
{
  "outputAliases": {
    "DP-2": "Main Monitor",
    "HDMI-A-1": "TV"
  }
}
```

## Work in Progress

- Preview image for the plugin registry
- More IPC commands for scripting (e.g. `addWorkspace`, `removeWorkspace`)

## Requirements

- Noctalia Shell 4.0.0 or later
- Niri compositor

## License

MIT
