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
- Inside instances (proven in Ragefire Chasm, party): `UnitPosition` and
  `C_Map.GetPlayerMapPosition` (the instance map and every ancestor) are
  nil, `C_Navigation` is off (state 0, no frame), and the rotating minimap
  ring is no oracle — `MinimapCompassTexture:GetRotation()` raises
  "forbidden aspect 'QueryRotation'" for tainted code and `GetTexCoord()`
  stays constant while the ring turns.
- `C_QuestLog.GetDistanceSqToQuest` still answers there: 2D yards² to the
  pin `C_QuestLog.GetQuestsOnMap` lists. Three pins trilaterate the player
  (`Nocturne_Compass/QuestFix.lua`). Checked outdoors against the real
  position (`/ncmp diag`, map 467, 4 pins): the fix matched
  `GetPlayerMapPosition` to within 0.003 yd. *(Unverified in-game: the
  compass running on it inside an instance, whose heading is the course
  over ground, not the facing.)*

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
- A bare `return` (or falling off the end) returns NO values, not `nil`:
  `tostring(f())` then errors "bad argument #1 to 'tostring' (value
  expected)". Helpers whose result goes straight into a call should end
  with an explicit `return nil`.

## Midnight (12.0) API quirks

- `BackdropTemplateMixin` does NOT exist as a `CreateFrame` template and its
  `HookBackdrop` method is gone. `Theme.ApplyBackdrop` tiers: native
  `frame:SetBackdrop` → guarded legacy `Mixin` fallback → no backdrop.
- Guard possibly-secret values with `issecretvalue` (`ns.IsSecret`) before
  math — Midnight marks combat-adjacent values secret. NOTE: the percent
  APIs (`UnitHealthPercent`/`UnitPowerPercent`) return secret values
  unconditionally — they're meant for `StatusBar`/`FontString` display, not
  Lua logic. Raw `UnitHealth`/`UnitPower` for "player" CAN still be secret
  with no active `C_RestrictedActions` entry and `canaccessvalue` false
  (observed on a live 12.x client: current values secret, max values
  readable). `C_Secrets.*` predicates report secrecy state but never expose
  values — there is no sanctioned secret comparison, so "at rest" style
  logic must track `UNIT_HEALTH`/`UNIT_POWER_*` event activity instead
  (see `Nocturne_Extra/Frames.lua`). StatusBars fed by Blizzard (PRD,
  PlayerFrame) are no oracle either: `GetValue`/`GetMinMaxValues` are secret.
- `UNIT_HEALTH_FREQUENT` no longer exists (folded into `UNIT_HEALTH` in
  9.0.1). `Nocturne.RegisterEvent` silently skips unknown events, so a stale
  event name fails without any error — count events in diag to prove they fire.
- `Mixin()` and `BackdropTemplateMixin` may both be missing; guard both.
- Prefer `GameTooltip:AddLine` over `SetText` (LSP annotations mismatch).
- The Personal Resource Display is `PersonalResourceDisplayFrame`
  (`Blizzard_PersonalResourceDisplay`, an Edit Mode system), NOT the
  player's nameplate — `C_NamePlate.GetNamePlateForUnit("player")` finds
  nothing. Its visibility follows the user's Edit Mode setting; fade it with
  `SetAlpha` on top, don't fight its Show/Hide.
- `C_Minimap.IsInsideQuestBlob` keeps answering with `MinimapCluster`
  hidden (observed: the in-region glow persisted with the minimap
  suppressed, even across a reload). Degrading the glow to pin distance while the minimap is
  away has to be done explicitly (`ns.MinimapShown()` gate in
  `TrackedQuests.lua`).
- `C_PlayerInteractionManager.IsValidNPCInteraction(Binder)` and
  `IsInteractingWithNpcOfType(Binder)` both return false while an
  innkeeper's shop (Merchant) is open — they describe the interaction in
  progress, not what the NPC can do. They can't classify an NPC; the
  `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` type already says the same.
- `C_TooltipInfo.GetUnit("npc").lines[i].leftText` holds an NPC's
  subtitle WITHOUT the angle brackets shown on screen: Innkeeper Grosk
  reads `Innkeeper Grosk | Innkeeper | Level 9 | Orgrimmar | PvP`. The
  subtitle matches the tracking menu's filter name (`Innkeeper`).
- Choosing an innkeeper's "Make this inn your home" gossip option fires
  `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` with `Binder` as soon as the
  confirmation popup opens — even if the player then clicks Cancel.
- *(Unverified — read from Blizzard's UI source, not yet proven in-game.)*
  The native Settings vertical layout has no free-text row: element
  initializers create their frames through the ScrollBox factory, which
  accepts a bare frame type ("Frame") in place of an XML template.
  `Builder:Text` (Core `Settings.lua`) uses that + an InitFrame override
  to render a description line; the extent is measured off a scratch
  FontString (element width ~620px).

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

## WoW Forever (Camelot, interface 16001)

- Same Mainline engine/API; installed as `_classic_beta_` (beta). The
  `.toc` lists `## Interface: 120001, 16001`; `Nocturne.IS_FOREVER` is
  interface 16000-16999. Blizzard's source: wow-ui-source branch `forever`.
- Edit Mode export strings differ: Midnight header `2 <count>`, Forever
  `4 <interfaceStyle> <count>` (Forever misreads a Midnight string: count
  lands in interfaceStyle). `Enum.EditModeSystem` and every setting enum
  match for 0-25; Midnight 26 LossOfControl is Forever 28; Forever adds 26
  MainActionBarEndCap, 27 GroupFinder (the queue eye; Midnight ties it to
  the micro menu), 29 SwingTimer. A user layout is enabled only when its
  interfaceStyle equals `InputUtil.GetCurrentInterfaceStyle()`. The bundled
  `FOREVER_LAYOUT` was applied and checked in-game.
- The native gamepad interface runs window focus in the name of whoever
  opens a Blizzard menu or UI panel; from addon code its
  `SetPreferredGamepadInteractTarget` is then refused
  (ADDON_ACTION_FORBIDDEN) until `/reload`. Proven: `MenuUtil.CreateContextMenu`
  from a click. Gate such opens with `Nocturne.GamepadRefuses`.
  Settings dropdowns call the addon's options function directly (no
  `securecallfunction`), so on Forever `Builder:Dropdown` is a slider.
  *(Unverified fix.)* Closing the Settings panel also raises it for other
  addons (seen for BugSack) — not Nocturne-specific.

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

## ConsolePort integration (verified)

- The action-bar skin lib is a LibStub library:
  `LibStub('ConsolePortActionButton')`; per-modifier skins live at
  `lib.Skin.ClusterBar[mod]` with mods `''`, `'SHIFT-'`, `'CTRL-'`,
  `'CTRL-SHIFT-'`. Swapping an entry restyles all already-created buttons
  (`Button:UpdateSkin` re-reads it).
- Cluster buttons are globally named `CPB_<ID>_<mod>` —
  e.g. `CPB_PAD1`, `CPB_PAD1_SHIFT`, `CPB_PAD1_CTRL_SHIFT` (`env.MakeID`
  maps `-`/` ` → `_` and strips a trailing `_`). Scan `_G` for `CPB_`
  prefixed names + a `.mod` field to find all cluster buttons.
- Presets applied via `ConsolePort('layout X')` are used RAW — no
  `BuildLayout`/`UpgradeInterface` pass fills interface defaults. Custom
  `ClusterHandle` tables must set every field (`type`, `pos`, `size`,
  `dir`, `showFlyouts`) or `Cluster:SetSize(props.size)` errors.
- Layout persistence: `env('Layout', …)` writes `ConsolePort_BarLayout`
  through a registered save callback; `env.Presets` proxies reads/writes
  to `ConsolePort_BarPresets`. The supported way to swap layouts is the
  slash handler — `ConsolePort('layout <presetName>')` — which wraps the
  swap in `env:RunSafe` (combat-safe) and refreshes the Manager.
- `ConsolePort` global has a `__call` metamethod bound to the slash
  dispatcher, so `ConsolePort('layout X')` is legal Lua.
- `SkinUtility.GetIconMask(button)` returns an existing IconMask or
  creates+attaches one — so overriding then restoring the mask texture is
  enough to toggle square vs. CP's wedge/round masks.
- *(Unverified — warcraft.wiki.gg `TextureBase:SetRotation`.)* Rotation
  transforms the image inside the region's unchanged box and scales it by
  2^-0.5, so a square rotated 45° is a diamond whose diagonal equals the
  box side. Pass `CLAMPTOBLACKADDITIVE` wrap modes to `SetTexture` so the
  area outside the rotated image is transparent.
- Cluster positions are set by `Cluster:SetPoint` → `ClearAllPoints` +
  `SetPoint` on the main button `CPB_<ID>`, relative to the cluster bar
  `ConsolePortBarCluster`; release clears its anchors.
- ConsolePort_Bar's internal `env` is not reachable from outside; only
  the lib, the `ConsolePort` callable, and the SavedVariables tables are
  public surfaces.

