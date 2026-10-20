class_name WeaponTuning
extends RefCounted
## The debug overlay's sliders per class of a weapon's resources (see `WeaponType`), the same for
## every weapon: each weapon gets a section per resource it's made of (see `debug_overlay.gd`). A
## row is a property, its lowest and highest value and its step.

const ROWS: Dictionary[String, Array] = {
	"WeaponType":
	[
		["attack_rate", 0.2, 20.0, 0.1],
		["draw_time", 0.0, 2.0, 0.05],
	],
	"DamageEffect":
	[
		["damage", 1.0, 200.0, 1.0],
		["stagger", 0.0, 100.0, 1.0],
		["push", 0.0, 10.0, 0.1],
	],
	"MagazineFeed":
	[
		["magazine", 1.0, 200.0, 1.0],
		["ore_per_round", 0.0, 5.0, 0.05],
		["reload_time", 0.1, 5.0, 0.05],
		["sweet_spot_start", 0.0, 1.0, 0.05],
		["sweet_spot_width", 0.0, 1.0, 0.05],
		["fumble_time", 0.0, 3.0, 0.05],
		["chain_speedup", 0.0, 0.5, 0.05],
		["max_chain_speedup", 0.0, 0.9, 0.05],
	],
	"HeatFeed":
	[
		["magazine", 1.0, 400.0, 1.0],
		["ore_per_round", 0.0, 1.0, 0.01],
		["reload_time", 0.1, 5.0, 0.05],
		["heat_per_round", 0.0, 0.2, 0.002],
		["cool_delay", 0.0, 3.0, 0.05],
		["cool_rate", 0.0, 2.0, 0.05],
		["vent_time", 0.1, 6.0, 0.1],
		["vent_from", 0.0, 1.0, 0.05],
		["sweet_spot_start", 0.0, 1.0, 0.05],
		["sweet_spot_width", 0.0, 1.0, 0.05],
		["fumble_time", 0.0, 3.0, 0.05],
	],
	"BatteryFeed":
	[
		["cells", 1.0, 60.0, 1.0],
		["recharge_delay", 0.0, 5.0, 0.05],
		["recharge_rate", 0.5, 30.0, 0.5],
		["drained_recharge_time", 0.1, 10.0, 0.1],
	],
	"SpinTrigger":
	[
		["spin_up", 0.0, 3.0, 0.05],
		["keep_spinning", 0.0, 5.0, 0.1],
		["spin_down", 0.0, 3.0, 0.05],
		["spinning_move_share", 0.0, 1.0, 0.05],
	],
	"ChargeTrigger":
	[
		["charge_time", 0.1, 5.0, 0.05],
		["min_power", 0.0, 1.0, 0.05],
		["charging_move_share", 0.0, 1.0, 0.05],
	],
	"ProjectileDelivery":
	[
		["speed", 5.0, 150.0, 1.0],
		["reach", 5.0, 60.0, 1.0],
		["pellets", 1.0, 20.0, 1.0],
		["spread", 0.0, 90.0, 1.0],
	],
	"LobDelivery":
	[
		["reach", 2.0, 40.0, 0.5],
		["stick_reach", 2.0, 40.0, 0.5],
		["speed", 2.0, 40.0, 0.5],
		["arc_per_meter", 0.0, 1.5, 0.05],
		["blast_radius", 0.5, 10.0, 0.1],
	],
	"ChargeDelivery":
	[
		["reach", 1.0, 20.0, 0.5],
		["blast_radius", 0.5, 10.0, 0.1],
		["charges", 1.0, 12.0, 1.0],
		["trigger_radius", 0.5, 6.0, 0.1],
		["arm_time", 0.0, 5.0, 0.1],
		["trip_time", 0.0, 2.0, 0.05],
	],
	"WellDelivery":
	[
		["reach", 2.0, 40.0, 0.5],
		["stick_reach", 2.0, 40.0, 0.5],
		["speed", 2.0, 40.0, 0.5],
		["blast_radius", 0.5, 12.0, 0.1],
		["hold_time", 0.2, 10.0, 0.1],
	],
	"ChainDelivery":
	[
		["reach", 2.0, 40.0, 0.5],
		["angle", 5.0, 180.0, 1.0],
		["jumps", 0.0, 12.0, 1.0],
		["jump_reach", 0.5, 15.0, 0.5],
		["jump_share", 0.0, 1.0, 0.05],
		["ground_reach", 1.0, 20.0, 0.5],
	],
	"ConeDelivery":
	[
		["reach", 1.0, 15.0, 0.5],
		["angle", 5.0, 120.0, 1.0],
	],
	"BeamDelivery":
	[
		["reach", 2.0, 60.0, 0.5],
		["ramp", 1.0, 10.0, 0.1],
		["ramp_time", 0.1, 10.0, 0.1],
	],
	"BurnEffect":
	[
		["damage_per_second", 0.0, 100.0, 0.5],
		["seconds", 0.0, 15.0, 0.1],
	],
	"HealEffect":
	[
		["heal", 0.0, 50.0, 0.1],
	],
	"ThrowEffect":
	[
		["distance", 0.0, 20.0, 0.5],
		["jab_distance", 0.0, 10.0, 0.25],
		["speed", 2.0, 40.0, 1.0],
		["landing_stagger", 0.0, 3.0, 0.05],
		["path_width", 0.1, 3.0, 0.05],
		["passed_share", 0.0, 1.0, 0.05],
		["aside", 0.0, 6.0, 0.25],
		["wall_share", 0.0, 2.0, 0.05],
		["wall_stagger", 0.0, 5.0, 0.1],
	],
	"PunchDelivery":
	[
		["reach", 0.5, 6.0, 0.1],
		["arc", 10.0, 180.0, 5.0],
	],
	"FieldFeed":
	[
		["charge", 10.0, 500.0, 5.0],
		["recharge_delay", 0.0, 5.0, 0.1],
		["recharge_rate", 1.0, 200.0, 1.0],
		["break_time", 0.0, 10.0, 0.1],
	],
	"WeaponGuard":
	[
		["arc", 30.0, 360.0, 5.0],
		["radius", 0.5, 3.0, 0.05],
		["height", 0.5, 4.0, 0.1],
		["open_after", 0.0, 1.0, 0.05],
		["open_time", 0.0, 1.0, 0.05],
		["move_share", 0.0, 1.0, 0.05],
		["shove", 0.0, 6.0, 0.25],
	],
	"SlowEffect":
	[
		["factor", 0.0, 1.0, 0.05],
		["seconds", 0.0, 3.0, 0.05],
	],
	"SwingDelivery":
	[
		["reach", 0.5, 6.0, 0.1],
		["arc", 10.0, 360.0, 5.0],
		["combo_gap", 0.1, 3.0, 0.05],
		["finisher_power", 1.0, 5.0, 0.1],
		["finisher_stagger", 1.0, 6.0, 0.1],
		["stroke_time", 0.0, 1.0, 0.05],
	],
	"ThrustDelivery":
	[
		["reach", 0.5, 10.0, 0.1],
		["width", 0.1, 3.0, 0.05],
		["drill_rate", 1.0, 30.0, 0.5],
		["drill_damage", 0.0, 1.0, 0.05],
		["drill_stagger", 0.0, 1.0, 0.05],
		["ramp", 1.0, 10.0, 0.1],
		["ramp_time", 0.1, 10.0, 0.1],
	],
	"DrillTrigger":
	[
		["drilling_move_share", 0.0, 1.0, 0.05],
		["spin_down", 0.0, 3.0, 0.05],
	],
}
