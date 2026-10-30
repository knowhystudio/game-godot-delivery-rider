extends RefCounted
class_name GameData
## Separate data tables. Code only reads these tables; tune numbers here.
## No real company / platform / person names anywhere in this project.

const VEHICLES = {
	"e_bike": {
		"name": "轻便电瓶车", "speed": 10.0, "accel": 18.0, "turn_speed": 6.0,
		"capacity": 2, "passability": "全部小巷", "parking_difficulty": 1,
		"spill_resist": 0.0, "colour": Color(1.0, 0.85, 0.1),
		"role": "末端", "can_alleys": true, "can_stairs": true,
	},
	"motorcycle": {
		"name": "摩托车", "speed": 14.0, "accel": 24.0, "turn_speed": 5.0,
		"capacity": 2, "passability": "不能进最窄小巷", "parking_difficulty": 2,
		"spill_resist": 0.10, "colour": Color(0.2, 0.6, 1.0),
		"role": "末端", "can_alleys": false, "can_stairs": true,
	},
	"car": {
		"name": "汽车", "speed": 13.0, "accel": 16.0, "turn_speed": 3.2,
		"capacity": 4, "passability": "仅主干道", "parking_difficulty": 4,
		"spill_resist": 0.25, "colour": Color(0.9, 0.3, 0.3),
		"role": "干线/中转", "can_alleys": false, "can_stairs": false,
	},
	"van": {
		"name": "面包车", "speed": 11.0, "accel": 13.0, "turn_speed": 2.6,
		"capacity": 6, "passability": "仅主干道", "parking_difficulty": 5,
		"spill_resist": 0.30, "colour": Color(0.5, 0.8, 0.4),
		"role": "干线/中转", "can_alleys": false, "can_stairs": false,
	},
}

# Order types. "vehicle_hint" is shown before accepting; in this slice the
# e-bike may still take all three types so the slice stays playable with
# one built vehicle. The hint is not a hard lock in the slice.
const ORDER_TYPES = {
	"light_meal": {
		"name": "轻食单", "pay": 30, "time_limit": 120.0, "spill_prone": 0.6,
		"vehicle_hint": "轻便型：单份轻食 / 单杯饮品", "weight": 1,
		"needs_small_last_100m": true, "needs_alleys": true,
	},
	"hot_soup": {
		"name": "热汤单", "pay": 45, "time_limit": 110.0, "spill_prone": 1.4,
		"vehicle_hint": "爬坡型：上坡热汤 / 易洒品", "weight": 1, "slow_merchant": true,
		"needs_small_last_100m": true, "needs_alleys": false,
	},
	"family_bag": {
		"name": "家庭大单", "pay": 60, "time_limit": 150.0, "spill_prone": 0.8,
		"vehicle_hint": "载货型：多单家庭 / 超市袋", "weight": 1,
		"needs_small_last_100m": false, "needs_alleys": false,
	},
}

const UPGRADES = [
	{"id": "big_box", "name": "大餐箱", "desc": "容量 +1（本局内）"},
	{"id": "damping", "name": "减震升级", "desc": "晃动积累 -30%"},
	{"id": "nitro_refill", "name": "氮气快充", "desc": "氮气恢复速度 +50%"},
]

# Battlefield props. Rarity drives pillar, icon frame and pickup feel, not
# just a number: normal = low pillar, epic = taller pillar, legendary =
# tallest pillar, and pop / flash / particle counts grow with rarity.
# extractable = carried out of the run into the out-of-run inventory at
# settlement. run-only = used in this run and lost at settlement.
# effect_id: stamina | nitrogen | capacity | integrity | starter | part | slot
# Red-team rarity spec (supersedes the first-slice pillar heights):
# normal = thin white-blue pillar 2m, smooth circle base, ring 1.0m;
# epic = purple-gold thick pillar 4m, hexagonal serrated base, ring 1.5m,
#   pillar rotates; legendary = rainbow pillar 8m, twelve-point radiating
#   base, ring 2.0m, slow-mo pickup, top-layer beam visible at distance.
# Rarity is NEVER colour alone: base shape, ring size, pillar height,
# pickup duration and behaviour all differ.
const PROP_TIERS = {
	"normal": {
		"name": "普通", "pillar_colour": Color(0.8, 0.9, 1.0),
		"pillar_height": 2.0, "icon_frame": "普通·灰框",
		"pop_scale": 1.3, "particle_count": 8, "flash_secs": 0.2,
		"base_shape": "circle", "ring_radius": 1.0,
		"pickup_secs": 0.0, "per_run_cap": 2,
	},
	"epic": {
		"name": "史诗", "pillar_colour": Color(0.6, 0.3, 1.0),
		"pillar_height": 4.0, "icon_frame": "史诗·紫框",
		"pop_scale": 1.6, "particle_count": 20, "flash_secs": 0.4,
		"base_shape": "hexagon", "ring_radius": 1.5,
		"pickup_secs": 0.5, "per_run_cap": 1,
	},
	"legendary": {
		"name": "传说", "pillar_colour": Color(1.0, 0.75, 0.1),
		"pillar_height": 8.0, "icon_frame": "传说·金框",
		"pop_scale": 2.0, "particle_count": 40, "flash_secs": 0.7,
		"base_shape": "twelve_point", "ring_radius": 2.0,
		"pickup_secs": 1.0, "per_run_cap": 1,
	},
}

# Props, read-only definitions. Code never mutates PROPS; per-run state
# lives in city props / main collected lists only.
# effect_id: stamina | nitrogen | capacity | starter | part | slot
# Epic/legendary props MUST give a new behaviour, not just a number:
#  nitro_can = instant nitrogen + 3s boost window (speed x1.2, grip halved);
#  grip_tyre = slope speed penalty eased + stamina drain halved on slopes;
#  golden_box = capacity +1 + 30s spill shield (spills do no damage);
#  tool_slot = second drive-away charge (2 charges, not just -cooldown).
const PROPS = {
	"drink": {
		"name": "补给饮料", "rarity": "normal", "extractable": false,
		"effect_id": "stamina", "effect_value": 30.0,
		"desc": "本局：体力 +30（用完不带出）",
	},
	"starter_pack": {
		"name": "开局补给包", "rarity": "normal", "extractable": true,
		"effect_id": "starter", "effect_value": 20.0,
		"desc": "可带出：下一局开始时 +14 金币（70%）、体力回满（消耗品）",
	},
	"nitro_can": {
		"name": "氮气大罐", "rarity": "epic", "extractable": false,
		"effect_id": "nitrogen", "effect_value": 100.0,
		"desc": "本局：氮气回满 + 3 秒爆发（速度 x1.2，期间防滑减半，互斥）",
	},
	"grip_tyre": {
		"name": "防滑轮胎", "rarity": "epic", "extractable": true,
		"effect_id": "part", "effect_value": 0.15,
		"desc": "可带出：车辆部件，下一局晃动抗性 +0.105（70%）、坡道减速减轻",
	},
	"golden_box": {
		"name": "金色餐箱", "rarity": "legendary", "extractable": false,
		"effect_id": "capacity", "effect_value": 1.0,
		"desc": "本局：容量 +1 + 30 秒防洒护盾（洒餐不扣完好度）",
	},
	"tool_slot": {
		"name": "多功能工具槽", "rarity": "legendary", "extractable": true,
		"effect_id": "slot", "effect_value": 0.7,
		"desc": "可带出：第二驱赶充能 + 冷却 -0.7 秒（70%，下一局生效）",
	},
}

# Explicit mutual exclusions (active effects, first slice only):
# grip_tyre (cargo stabilisation) does not stack with golden_box
# (spill shield); when the shield is active, the grip bonus is suspended.
const PROP_EXCLUSIONS = {
	"grip_tyre": ["golden_box"],
	"golden_box": ["grip_tyre"],
}

# Extraction rules (red-team): at most 1 epic + 1 legendary carried out
# per run; cost 5% of run reward per epic, 10% per legendary; extractable
# effects apply at 70% next run; run upgrades never extract.
const EXTRACTION = {
	"max_epic_per_run": 1, "max_legendary_per_run": 1,
	"epic_cost_rate": 0.05, "legendary_cost_rate": 0.10,
	"next_run_effect_rate": 0.7, "difficulty_step": 0.02,
	"difficulty_max": 0.10, "extraction_point_time_cost": 10.0,
	"exploration_detour_time_cost": 20.0,
}

# Skills: cap 6 per run, at most 2 drive-away tools. Other skills rotate
# via equipment / props. Costs are explicit: no free spamming.
const SKILLS = [
	{"id": "drive_away", "name": "驱赶", "kind": "drive_away",
		"nitrogen_cost": 15.0, "stamina_cost": 5.0, "cooldown": 3.0},
	{"id": "urge", "name": "催商家", "kind": "urge",
		"nitrogen_cost": 0.0, "stamina_cost": 10.0, "cooldown": 4.0},
	{"id": "nitrogen", "name": "氮气", "kind": "move",
		"nitrogen_cost": 30.0, "stamina_cost": 0.0, "cooldown": 0.0},
	{"id": "steady", "name": "稳餐", "kind": "defence",
		"nitrogen_cost": 0.0, "stamina_cost": 15.0, "cooldown": 5.0},
]
const SKILL_CAPS = {"max_active": 6, "max_drive_away": 2}

# Overall stat caps: spill resist 50%, speed 130% of base, range 150%.
const STAT_CAPS = {
	"spill_resist_max": 0.5, "speed_rate_max": 1.3, "range_rate_max": 1.5,
}

# Tuning panel ranges: hard range = refuse outside, safe range = yellow
# warning outside but allowed, orange = confirm step before applying.
const TUNING = {
	"spill_damage": {"hard": [10.0, 30.0], "safe": [15.0, 25.0], "default": 20.0},
	"tool_cooldown": {"hard": [2.0, 5.0], "safe": [2.5, 4.0], "default": 3.0},
	"nitrogen_drain": {"hard": [20.0, 40.0], "safe": [25.0, 35.0], "default": 30.0},
	"version": 1,
}

# Fixed battlefield spawns, on-route, not detours. Order matches PROPS keys.
const PROP_SPAWNS = [
	{"id": "drink", "pos": Vector3(12, 0, -12)},
	{"id": "starter_pack", "pos": Vector3(-18, 0, 18)},
	{"id": "nitro_can", "pos": Vector3(24, 0, 20)},
	{"id": "grip_tyre", "pos": Vector3(-24, 0, -18)},
	{"id": "golden_box", "pos": Vector3(30, 0, -20)},
	{"id": "tool_slot", "pos": Vector3(-6, 0, -24)},
]

const BALANCE = {
	"shake_decay_per_sec": 25.0,
	"spill_threshold": 100.0,
	"spill_damage": 20.0,
	"spill_reset": 60.0,
	"nitrogen_max": 100.0,
	"nitrogen_drain_per_sec": 30.0,
	"nitrogen_refill_per_sec": 12.0,
	"stamina_max": 100.0,
	"tool_cooldown": 3.0,
	"tool_nitrogen_cost": 15.0,
	"tool_stamina_cost": 5.0,
	"urge_cooldown": 4.0,
	"urge_stamina_cost": 10.0,
	"tool_slow_secs": 2.0,
	"tool_slow_rate": 0.7,
	"tool_range": 8.0,
	"tool_fan_degrees": 60.0,
	"on_time_bonus": 10,
	"zero_spill_bonus": 10,
	"roadside_reward_coins": 15,
}
