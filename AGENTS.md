# AGENTS.md — rules for this repo

## Scope

Monorepo of World of Warcraft **Midnight (12.x, `## Interface: 120001`)** addons.
Goal: calm, console-like UI that is easy on the eyes. No external dependencies —
no Ace libraries, no HereBeDragons. Only Blizzard APIs.

## Naming / collision rules

- Addon folders: `addons/Nocturne_<Feature>/`, `.toc` file same name.
- Allowed globals: `_G.Nocturne` (shared namespace), `Nocturne<Feature>DB`
  (SavedVariables), `Nocturne<Feature>_<name>` only for functions the client
  resolves by name (e.g. `AddonCompartmentFunc`).
- Frame names: `Nocturne<Feature><Role>` (e.g. `NocturneCompassFrame`).
- Everything else is `local` or lives in the private namespace:
  `local _, ns = ...` (or `local ADDON_NAME, ns = ...`).
- `Nocturne_Core` is required by every addon (`## Dependencies: Nocturne_Core`).

## Verified WoW facts (do NOT "fix" these — they were proven on the live client)

World coordinates (`C_Map.GetWorldPosFromMapPos`) and facing:

- World deltas: **+x = north, +y = west** — the world axes are rotated 90°
  relative to map orientation (map +x = east, +y = south).
- `GetPlayerFacing()`: **radians CCW from north** (0 = N, turning left
  increases). Convert to a CW compass bearing with `facingCW = (2π - facing) % 2π`.
- Direction of a world delta to CW bearing: `atan2(-dy, dx) % 2π`.
- A relative angle `rel = WrapAnglePi(bearing - facingCW)` is >0 when the
  target is to the RIGHT of the heading.
- `C_Map.GetPlayerMapPosition` + `C_Map.GetWorldPosFromMapPos` is used for the
  player's own world position so both ends share one coordinate frame.
- `C_QuestLog.GetDistanceSqToQuest` measures distance to the quest **pin**, not
  to the nav-arrow anchor (nav arrow can sit ~30y closer, at the same bearing).
- `C_SuperTrack.GetNextWaypointForMap` only returns a waypoint for transit
  (cross-map); it returns nil for same-map quests.
- `GetPlayerFacing()` returns nil inside instances — use it as the
  "cannot navigate" signal.

## General WoW UI gotchas (not Midnight-specific, learned the hard way)

- `Frame:GetCenter()/GetLeft()/GetWidth()` etc. return coordinates in that
  frame's OWN local/effective scale, NOT a shared screen-pixel space. Two
  frames with different `SetScale()` (e.g. a size-varying marker icon vs its
  unscaled parent) are NOT directly comparable by subtracting their
  `GetCenter()` results — normalize both with `x * frame:GetEffectiveScale()`
  first.
- `SetPoint(..., xOfs, yOfs)` offsets are in the ANCHORED frame's own scaled
  space, not the anchor target's: a marker with `SetScale(1.5)` anchored at
  `xOfs = 100` lands 150 parent units away. Divide the offset by the frame's
  own scale (`x / scale`) to position it in the parent's units. Proven via
  `/ncmp diag` (renderXY = x * markerScale * UIScale for every marker).
- `local a, b = x and f()` (or any `and`/`or` on the right of a multi-value
  assignment) silently truncates to one value — `and`/`or` always collapse
  to a single result even when the right operand returns multiple. Guard
  with an `if`, don't rely on `and` to short-circuit a multi-return call.

## Midnight (12.0) API quirks

- `BackdropTemplateMixin` does NOT exist as a `CreateFrame` template and its
  `HookBackdrop` method is gone. `Theme.ApplyBackdrop` tiers: native
  `frame:SetBackdrop` → guarded legacy `Mixin` fallback → no backdrop.
- Guard possibly-secret values with `issecretvalue` (`ns.IsSecret`) before
  math — Midnight marks combat-adjacent values secret.
- `Mixin()` and `BackdropTemplateMixin` may both be missing; guard both.
- Prefer `GameTooltip:AddLine` over `SetText` (LSP annotations mismatch).

## DRY

- Never duplicate logic across addons — shared behavior (logging, theming,
  event bus, math helpers, popups, marker pooling, etc.) belongs in
  `Nocturne_Core` (or a shared module) and is reused, not copy-pasted.
- Within an addon, extract repeated patterns (e.g. building a font string,
  registering a group of events, pooling widgets) into a single local
  helper function instead of inlining the same code at each call site.
- Before adding a new helper, check `Nocturne_Core` and the current addon
  for an existing one that already does it.

## WoW addon best practices (from community guidelines)

- **Locals over globals**: cache frequently used globals/API functions as
  locals at file scope (`local UnitPosition = UnitPosition`), especially
  anything touched from `OnUpdate` or per-frame code — local access is
  faster and avoids accidental global pollution/taint.
- **Events over polling**: prefer `RegisterEvent`/`RegisterUnitEvent` to
  react to state changes; `OnUpdate` runs every rendered frame and is
  reserved for animation or things that must track continuously (e.g. the
  compass's own bearing math). For unit-specific data prefer
  `RegisterUnitEvent` over broad events.
- **Throttle anything hot**: if code must run in `OnUpdate` or on a
  high-frequency event (e.g. `BAG_UPDATE`, `ZONE_CHANGED`), accumulate
  elapsed time and only do work every N ms, or debounce with
  `C_Timer.After`/`C_Timer.NewTicker` instead of polling.
- **Avoid per-frame table/string churn**: don't allocate new tables or
  concatenate strings inside `OnUpdate` or tight loops — reuse a scratch
  table (`table.wipe` to clear) and avoid building strings you don't need
  to display that frame.
- **Pool widgets**: dynamic UI elements (markers, buttons, rows) must be
  created once and reused via a pool keyed by a stable id, not recreated
  every update (see `Markers.lua`'s marker pool).
- **SavedVariables are nil at file load**: never read/write a `*DB` global
  at chunk top level; initialize/merge defaults inside `ADDON_LOADED` (and
  always check `loadedAddon == ADDON_NAME`, since the event fires for every
  addon).
- **Async data (spells/items) needs a fallback**: `C_Spell`/`C_Item` getters
  can return nil on first call if data isn't cached yet; either request the
  load (`C_*.RequestLoadItemData`/`RequestLoadSpellData`) and listen for the
  `*_DATA_LOAD_RESULT` event, or tolerate a nil/placeholder for one frame.
- **Don't fight taint**: never reuse Blizzard's frame/variable names
  (`arg1`, secure frame fields) and don't call protected API from insecure
  code paths.

## Conventions

- Style: plain Lua, compact, Blizzard-ish naming (`camelCase` functions,
  `UPPER_SNAKE` for slash commands). No comments unless they carry verified
  knowledge (API quirks, conventions).
- Visuals: Blizzard-native look — `UI-Tooltip-Background` / `UI-Tooltip-Border`
  via `Theme.ApplyBackdrop`; theme constants live in `Nocturne_Core/Theme.lua`.
- Shared helpers go into `_G.Nocturne` (`Print`, `Debug`, `RegisterModule`,
  `RegisterEvent`, `ShowCopyText`, `Theme`) — defined in `Nocturne_Core`.
- Per-addon state lives in `ns`; SavedVariables defaults in `DB.lua` merged
  over `ns.defaults`.
- Settings use the native `Settings` API (`RegisterAddOnCategory`,
  `RegisterAddOnSetting`, checkboxes/sliders) — no custom options panels.
- Slash commands: `/n<feature>` and a 3-4 letter alias (`/ncmp`).

## Diagnostics

- Keep a `/ncmp diag`-style command that opens `Nocturne.ShowCopyText` (a
  copyable popup) — addons cannot write to the clipboard.
- Never trust bug reports' timestamps alone: same timestamp + same stack =
  stale BugSack entry, ask the user to clear/reload first.

## Verification

- After every change: `tools/check.sh` (luajit syntax check) — must print `OK`.
- Lua syntax is 5.1-compatible (no `goto`, integer division `//`, etc.).
- In-game behavior can't be verified locally — give the user a concrete
  test protocol (`/reload`, what to face, what to run, what to paste).

## Git

- Branch `master`, conventional one-line commits + `Generated with Devin`
  footer. Never commit secrets. Do not overwrite user edits in .toc files
  (e.g. version fields) unless asked.
