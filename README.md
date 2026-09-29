# Nocturne

A monorepo of World of Warcraft (Midnight, 12.x) addons focused on a calm,
console-like UI that is easy on the eyes.
**Due to the fact that I don't have time to learn LUA and WoW addons development I've decided to use AI tools write the code.**

## AI-assisted development

This project is developed with the help of AI coding agents (Devin), under
human direction and review. Design decisions, in-game testing and final
review are done by a human; the agent writes/edits code, researches the WoW
API, and iterates based on real in-game diagnostics. See `AGENTS.md` for the
project rules and WoW/Lua conventions the agent (and any contributor) follows.

## Addons

| Folder | Description |
| ------ | ----------- |
| `addons/Nocturne_Core` | Shared namespace, theme (colors/fonts) and event bus used by every Nocturne addon. Required by all other addons in this repo. |
| `addons/Nocturne_Compass` | Console-style navigation strip: heading, cardinal points and markers for your tracked quests. Markers grow as you approach and fade/pulse into a banner when you enter the quest area. |

## Install (development)

Symlink the addon folders into your client's AddOns directory:

```bash
tools/install.sh "/path/to/World of Warcraft/_retail_"
```

Remove the created symlinks from `Interface/AddOns` to uninstall.

## Syntax check

```bash
tools/check.sh
```

Requires `luac` or `luajit` on PATH.

## Naming rules (no collisions with other addons)

- Addon folders: `Nocturne_<Feature>`.
- Globals allowed: `_G.Nocturne` (shared namespace), `Nocturne<Feature>DB`
  (SavedVariables), and `Nocturne<Feature>_<name>` only for functions the
  client requires by name (`AddonCompartmentFunc`, bindings).
- Frame names: `Nocturne<Feature><Role>` (e.g. `NocturneCompassFrame`).
- Everything else stays `local` or lives in the addon's private namespace
  table received via `local _, ns = ...`.
