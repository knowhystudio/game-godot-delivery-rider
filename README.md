# Delivery Rider — First Playable Godot Slice (local only)

Godot 4.3 project. No GitHub repo, no publishing, no real names, no licensed
assets — every visual is a built-in primitive mesh with a plain colour.

## Playable demo (built, not just a README)

Web export (open in a browser, needs a local static server — browsers
block file:// wasm in some cases):

```bash
cd ~/workspace/delivery-game/exports/web
python3 -m http.server 8000
# then open http://localhost:8000/index.html
```

Linux export (same folder as the web export, 64 MB binary + .pck):

```bash
~/workspace/delivery-game/exports/linux/delivery-rider.x86_64
```

Both exports were built with Godot 4.3 export templates (downloaded
official 4.3-stable templates; web = nothreads release, linux = release
x86_64). The Linux binary was run headless for 5 s with no SCRIPT ERROR;
the web files were checked for completeness (index.html + index.js +
index.wasm 34 MB + index.pck containing the prop/save scripts) but were
NOT played in a real browser on this VM — see "What was NOT verified".

## How to run from source

You need Godot 4.3. The binary used for testing lives at
`~/workspace/tools/Godot_v4.3-stable_linux.x86_64` (downloaded from the
official Godot 4.3-stable release); any Godot 4.3 editor works the same way.

```bash
# Open in the editor, or run the game directly:
Godot_v4.3-stable_linux.x86_64 --path ~/workspace/delivery-game
# Headless smoke run (5 seconds, no window):
Godot_v4.3-stable_linux.x86_64 --headless --path ~/workspace/delivery-game --quit-after 5
```

Main scene: `scenes/main.tscn`.

## Controls (updated)

- WASD / arrows — ride
- Shift — nitrogen boost (drains nitrogen, refills slowly)
- Tab (hold) — aim mode: camera zooms slightly out, semi-transparent fan
  indicator appears in front of the rider
- Space / Q — drive-away tool (fan in front, 8 m, 3 s cooldown, 15 nitrogen
  + 5 stamina, separate cooldown from urge; 2 charges with tool_slot)
- E — pick up at a merchant / deliver at a customer
- F — urge a slow merchant (only in a slow pickup zone < 2.8 m/s near a
  merchant, 10 stamina, 4 s cooldown, three-stage mood meter)
- R — report once per order (merchant-caused timeout is partly offset)
- 1 / 2 / 3 — accept order 1 / 2 / 3
- Vehicle selector (top-right of the button area) — e-bike / motorcycle /
  car / van per order; large trunk/transfer vehicles are refused on
  orders needing alleys or the last 100 m on a small vehicle.
- "提取登记" — register props for extraction at the extraction point
  (south grey box, 10 s time cost); unregistered extractables are lost.
- "放弃本班" — failed run: inventory halved, no extraction.
- "调参面板" — internal tuning panel (L1 unlocked, L2/L3 locked,
  snapshot/rollback, yellow/orange/red ranges).
- All of the above also have on-screen buttons (mouse / touch fallback).

## Controls

- WASD / arrows — ride
- Shift — nitrogen boost (drains nitrogen, refills slowly)
- Tab (hold) — aim mode: camera zooms slightly out, semi-transparent fan
  indicator appears in front of the rider
- Space / Q — drive-away tool (fan in front, 8 m, 3 s cooldown)
- E — pick up at a merchant / deliver at a customer
- F — urge a slow merchant (only at the merchant, while food is still preparing)
- R — report once per order (merchant-caused timeout is partly offset)
- 1 / 2 / 3 — accept order 1 / 2 / 3
- All of the above also have on-screen buttons (mouse / touch fallback).

## What is playable in this slice

- One district, one station (route centre, spawn / rest / resupply point),
  one e-bike. Motorcycle / car / van exist only as data in
  `scripts/game_data.gd` — not built as vehicles yet, by scope.
- Third-person panoramic camera behind and above the rider, minimap
  top-right (player, merchants, customers, station, roadside reward,
  blockers, dashed suggested route to the next target).
- Three order types, shown before accepting with vehicle hint and pay:
  light meal, hot soup (slow merchant), family bag.
- Up to 2 simultaneous orders (e-bike capacity); free route order, changing
  route costs nothing; suggested route is dashed and optional.
- Countdown per order with a red visual pulse under 15 s (visual only —
  no heartbeat audio / vibration in this slice).
- Spill / shake meter with forgiveness: shake builds with speed and turning,
  decays when riding smoothly, hits 100 → integrity −20% and shake resets to 60.
- One drive-away tool: clears blockers in a fan in front of the rider
  (blockers return after 20 s), and the same tool urges a slow merchant:
  first urge cuts remaining prep to 40%, second to 70%, third+ adds 2 s and
  risks a mid review. One report per order partly offsets a merchant-caused
  late penalty at settlement.
- One roadside reward on the main crossroad (not a detour): +15 coins, +20 stamina.
  Pet fetch radius is 6 m (3.5 m without an active pet).
- Exploration reward in the mountain corner (off-route): +30 coins, -20 s
  detour time cost, clearly marked.
- Battlefield props (6, see `scripts/game_data.gd` PROPS): normal thin
  white-blue pillar 2 m, epic purple-gold thick pillar 4 m rotating,
  legendary rainbow pillar 8 m with slow-mo pickup; base shape, ring
  size, pickup duration (0 / 0.5 / 1.0 s) and behaviour differ by rarity,
  never colour alone. Run-only props are used in-run and lost;
  extractable props (starter pack, grip tyre, tool slot) are carried out
  only if registered at the extraction point, at most 1 epic + 1
  legendary per run, costing 5% / 10% of run reward, at 70% effect next
  run. Settlement is step-by-step: conclusion (cannot be skipped) →
  detail (kept / converted / lost, with sources) → inventory sync
  (at least 2 s, legendary row locked, discard needs double confirmation,
  skip only after 2 s). Out-of-run inventory is saved to
  `user://delivery_inventory.json` (main + backup slot, rollback on
  corrupt file); successful extraction raises next-run difficulty
  slightly (time limits -2% per step, max -10%). Run upgrades never extract.
- Pet: dedicated mount slot (side seat), fatigue (fast riding tires it,
  100% = rests, recovers near station); never picks up orders, never
  blocks drive-away judgement.
- Active effects bar (max 4 permanent, +N folding, mm:ss, 30 s yellow /
  10 s red), minimap heading-up with speed-adaptive zoom and only one
  route line, pillars fading near-transparent within 10 m, slip as an
  edge effect only, countdown on top.
- Red-team rules, implemented vs not-yet: see `RED_TEAM_NOTES.md`.
- After 2 deliveries, a three-choice upgrade appears (bigger box +1 capacity /
  damping −30% shake / nitrogen refill +50%). After 3 deliveries or “结束本班”,
  a settlement screen shows coins, reputation, delivered count, spills and lates.
- Slope / mountain road on the west side (x < −30): slower, costs stamina.
  Station area refills stamina.

## Scene split (Zcode structure)

- `scenes/main.tscn` + `scripts/main.gd` — run: city, station, orders, time, minimap
- `scenes/city.tscn` + `scripts/city.gd` — roads, buildings, stairs, merchants,
  customers, blockers, roadside reward
- `scenes/rider.tscn` + `scripts/rider.gd` — rider + vehicle + box + pet seat +
  tool mount in one swappable scene; changing vehicle only changes parameters
- `scenes/station.tscn` + `scripts/station.gd` — per-stage station
- `scenes/ui.tscn` + `scripts/ui.gd` + `scripts/minimap.gd` — UI only:
  countdown, order list, route hints, three-choice upgrade, reputation, settlement
- `scripts/game_data.gd` — all tunable numbers (vehicles, orders, upgrades, balance)
- `scripts/logic.gd` — pure formulas (urge, spill, settlement, review)

## Art direction (Codex descriptions, reference only — not built visuals)

Third-person panoramic camera behind and above the rider, slight top-down
view, minimap top-right, drive-away targets distinguished by shape/icon and
outline (not colour alone), dodge targets show only a predicted trajectory,
bright rounded slightly exaggerated cartoon 3D, fictional geometric logos
with no text, delivery-themed funny tools, no guns. City panorama: mountain
winding road left, dense commercial centre, waterfront right, outdoor stairs
and community entrance near, delivery points in all directions with different
flag shapes and dashed routes. Vehicles determine delivery type (light /
cargo / slope, same scale). Per-stage station: one floor + mezzanine, yellow
and dark grey, fictional emblem, order board with shape cards, front yard
split parking/charging / pickup/sorting / repair/upgrade / rest-team.

## Tests (verified headless)

```bash
Godot_v4.3-stable_linux.x86_64 --headless --path . --script res://scripts/test_slice.gd
# PASS all slice logic tests
Godot_v4.3-stable_linux.x86_64 --headless --path . res://scenes/test_play.tscn
# PASS play-through: 3 delivered, coins=185 (195 - 5% epic extraction cost),
# reputation=106, capacity=3, props+extraction ok
```

## What was NOT verified

- Visual play on a real screen / phone: this VM has no GUI, so the game was
  only run headless. The headless dummy renderer logs repeated
  `mesh_get_surface_count` “Parameter m is null” errors; no SCRIPT ERROR
  appears and both tests pass, but the actual look (proportions, readability,
  minimap legibility, camera feel) is unverified until someone opens it in
  the Godot editor / on a device.
- Keyboard feel (turning, nitrogen, tool aim) and the mountain-road collision
  behaviour were not played by a human.
- No sound, no vibration, no collection atlas, no multi-district map, no
  motorcycle / car / van vehicles — all deliberately out of this slice.

## What remains

- Human play-test in the editor / on a device, then tune numbers in
  `game_data.gd` from play data (not by guessing).
- Build the other vehicles as rider-scene variants using the existing
  vehicle table, then per-stage stations, then the collection layer.
- Replace primitive meshes with Codex / Forge art only when that art exists
  and matches the third-person panoramic direction above.
