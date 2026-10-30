# Red-team rules — implemented vs not yet (first slice + props only)

Scope guard: nothing beyond the first slice + props was built. Anything
listed as "not yet" is a deliberate deferral, not an oversight claim.

## 1. Skills (red-team fault list) — implemented
- Every skill has an explicit cost: drive-away = 15 nitrogen + 5 stamina,
  3s cooldown (2.3s with tool_slot at 70%); urge = 10 stamina, 4s cooldown,
  separate from drive-away (separate buttons, separate cooldowns).
- No free spamming: drive-away checks charges, nitrogen and stamina.
- Move + drive-away never stack at full power: 2s at 70% speed after a
  tool use; speed overall capped at 130% of base.
- Tool charges: 1 normally, 2 with tool_slot (second charge is a new
  behaviour, not just a number).

## 2. Props — implemented
- Pillars (red-team spec): normal thin white-blue 2m, epic purple-gold
  thick 4m rotating, legendary rainbow 8m with slow-mo pickup (0.3x, 0.8s).
- Rarity never colour alone: base shape (circle / hexagon / twelve-point),
  ground ring size (1.0 / 1.5 / 2.0m), pillar height, pickup duration
  (0 / 0.5 / 1.0s channelled), pop scale, particle count, float text.
- Same-name caps per run: normal 2, epic 1, legendary 1 (enforced on pickup).
- Overall caps: spill resist 50%, speed 130%, drive-away range 150%.
- Mutual exclusion (first slice, one pair): grip_tyre <-> golden_box
  (both stabilise cargo; shield suspends the grip bonus while active).
  Full exclusion matrix: NOT YET.
- Epic/legendary new behaviours: nitro_can = nitrogen + 3s boost window
  (grip halved during boost); grip_tyre = slope penalty eased + stamina
  drain halved on slopes; golden_box = capacity +1 + 30s spill shield;
  tool_slot = second drive-away charge.

## 3. Extraction — implemented
- Run-only = temporary numbers, lost at settlement. Extractable = defined
  items at 70% effect next run (starter +14 coins, grip +0.105 resist,
  tool_slot cooldown -0.7s + second charge).
- At most 1 epic + 1 legendary carried out per run; extras convert to
  +10 coins each. Cost: 5% of run reward per epic, 10% per legendary.
- Failed run (abandon): inventory halved, no extraction, no difficulty rise.
- Next-run difficulty rises +1 step (2% time-limit shrink, max 10%)
  after a successful extraction — anti-snowball.
- Run upgrades never extract (tested: upgrade ids are not prop ids).
- Data separation: GameData.PROPS is read-only, per-run prop instances
  are respawned on every reset, extraction writes only id (+tier via
  definition) to the save, main + backup slots, rollback on corrupt file.

## 4. Panel (tuning, first slice) — partially implemented
- Implemented: per-level presets independent (L1 unlocked, L2/L3 locked),
  dirty flag kept across level switches, safe ranges with yellow warning /
  orange confirm (two-press apply) / red refuse (hard-range clamp +
  validate function), version label v1, snapshot + rollback buttons.
- NOT YET: stage tree, batch apply, before/after comparison, field-level
  merge beyond per-field preset restore, auto-snapshot before/after
  playtests (manual snapshot only), save isolation from test runs
  (tuning values are runtime-only in this slice, not persisted).

## 5. Vehicle progression (Codex corrections) — implemented as rules
- Vehicles selectable per order via the UI selector; acceptance gate
  refuses large trunk/transfer vehicles (car/van) on orders needing
  alleys or the last 100m on a small vehicle, so large-vehicle orders
  cannot soft-lock. Large vehicles are labelled 干线/中转.
- NOT YET (built vehicles): only the e-bike is a built rider scene;
  motorcycle/car/van exist as data + selector colour/speed changes only.
  Full vehicle models, walking last-100m mode, and high-rise order
  forcing rules are next steps, not in this slice.

## 6. Skills / pet / overload (Codex) — implemented
- Active skills cap 6 per run, at most 2 drive-away tools (validated).
- Pet: dedicated mount slot (side seat), fatigue (fast riding tires it,
  100% = rests, recovers near station), never picks up orders, never in
  the blocker list, so never blocks drive-away judgement.
- Overload: normally only next order + margin shown; full route
  comparison only when stopped/slow (<1 m/s); pulse only in the last
  15s, off after severe lateness (< -30s).
- Extraction point vs station: early stage keeps a separate extraction
  point (south, grey box, 10s time cost, must register before settlement);
  later stages merge into station settlement (not built yet).
- Roadside rewards split: on-route reward (no detour, pet fetch radius
  6m) vs exploration reward (mountain corner, +30 coins, -20s detour
  cost shown on pickup).

## 7. UI (Doubao) — implemented / partial
- Implemented: rarity shape/texture/rhythm/symbols, ring sizes, pillar
  heights, pickup durations; skill buttons angular vs prop floats
  rounded-square, different cooldown masks (buttons show seconds +
  colour, props show none); popup titles 24px vs 20px (diff 4px);
  active effects bar: max 4 permanent, icon labels 28px, layer count
  "x1", time mm:ss, 30s yellow / 10s red, +N folding; settlement
  step-by-step (conclusion cannot be skipped, detail by kept/converted/
  lost with source labels, sync at least 2s, legendary row 80% width
  locked by default, dangerous discard separated and double-confirmed,
  skip only after 2s); warning layering (countdown z 10 on top, urge
  as bottom tip, slip as edge effect only).
- NOT YET: sound patterns per rarity (no audio in this slice); synergy
  links drawn as thin lines (shown as a text row only when applicable,
  no drawn lines yet); expired-effect 1.5s reason tip (expiry is shown
  via the effects bar disappearing + a message, not a timed 1.5s tip);
  full tuning panel (stage tree, batch, before/after — see §4).

## 8. Internal tuning-panel rules (Gemini, Muse-only) — implemented / partial
- Implemented: central road-ahead area clear (no permanent centre
  panel; upgrade/settlement only when not driving); one main ground
  route line only (minimap dashed line to next target, others are
  icons / edge indicators); minimap heading-up, player centred,
  speed-adaptive zoom (fast = wider range); pickup pillars fade to
  near-transparent within 10m and have no collision, so never block
  obstacles; driving locks detail popups (full order list only when
  stopped/slow); legendary pickup is a non-blocking top banner
  (float label), never a modal; urge button only replaces the throw
  button inside a slow pickup zone (<2.8 m/s) near a merchant, with a
  three-stage mood meter (心情好 / 有点不耐烦 / 快发火了, green/yellow/
  red); large-vehicle no-entry warning within 40m of an alley order;
  expanded loading zones with pet fetch (6m radius); impossible
  time-limit red block on accept; tuning dirty state across level
  switches, snapshot/rollback.
- NOT YET: 3D holographic no-entry walls (HUD warning only; alley
  geometry for a real wall is not defined in this slice); 3D turning
  trajectory lines at low speed (minimap dashed route covers this at
  low speed); auto snapshot before/after playtests; field-level merge
  on conflicts beyond per-field preset restore; red blocking for
  impossible MAPS (time-limit blocking is implemented, map-layout
  validation is not).

## Tests covering the above
- `scripts/test_slice.gd`: pillar heights 2/4/8, per-run caps, stat
  caps, mutual exclusion, vehicle gate, skill caps, tuning validate
  ok/yellow/orange/red, upgrade-not-prop, save round-trip, difficulty,
  rollback.
- `scenes/test_play.tscn`: full run + drink stamina + grip extraction
  registration + extraction cost (195 -> 185) + settlement steps 1-3
  with 2s sync.
