extends "res://tests/test_case.gd"
## Every event the sim can emit is either handled by a presenter or deliberately ignored, with a reason.
## And no event may carry a field that collides with the "kind" key the sim stamps on every event.

const Events = preload("res://scripts/sim/events.gd")
const Juice = preload("res://scripts/view/juice.gd")
const SynthSfx = preload("res://scripts/adapters/synth_sfx.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Loader = preload("res://scripts/data/rules_loader.gd")
const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")
const Bot = preload("res://scripts/batch/simple_bot.gd")
const K = Events.Kind
## Every presenter play_mode feeds events to (play_mode._presenters). Each declares HANDLED.
const PRESENTERS := [Juice, SynthSfx, preload("res://scripts/adapters/device_haptics.gd"),
	preload("res://scripts/ui/hud.gd"), preload("res://scripts/audio/music_player.gd")]

## Events no presenter needs to show; each is logged by the sim or read from state instead.
const IGNORED := {
	K.ENEMY_SPAWNED: "enemies are drawn from sim state",
	K.ENEMY_ESCAPED: "an enemy leaving the road needs no feedback",
	K.UPGRADE_SPAWNED: "drawn from sim state; logged",
	K.UPGRADE_EXPIRED: "drawn from sim state; logged",
	K.TRAP_SPAWNED: "drawn from sim state; logged",
	K.TRAP_EXPIRED: "a trap that passes harmlessly needs no feedback; logged",
	K.TOWER_EXPIRED: "tower blinks before it goes (actors); logged",
}


func test_every_event_kind_is_handled_or_ignored() -> void:
	for kind in K.values():
		var handled: bool = IGNORED.has(kind)
		for presenter in PRESENTERS:
			handled = handled or presenter.HANDLED.has(kind)
		ok(handled, "%s has no presenter and is not in IGNORED" % Events.kind_name(kind))


## A new weapon in weapons.tsv must not go silent or skip its vibration.
func test_every_weapon_has_a_sound_and_a_haptic_kick() -> void:
	var rules = load("res://scripts/data/rules_loader.gd").load_rules()
	var sfx := SynthSfx.new()
	sfx._ready()
	var haptics = load("res://scripts/adapters/device_haptics.gd")
	for id in rules.weapons:
		ok(sfx._clips.has("shot_" + id), "no fire sound for weapon '%s'" % id)
		ok(haptics.FIRE.has(id), "no haptic entry for weapon '%s'" % id)
	for p in sfx._players:
		p.free()
	sfx.free()


func test_ignored_kinds_are_not_also_handled() -> void:
	for kind in IGNORED:
		for presenter in PRESENTERS:
			ok(not presenter.HANDLED.has(kind), "%s is both ignored and handled" % Events.kind_name(kind))


## Regression: PICKUP and UPGRADE_SPAWNED used a "kind" field for the reward type, which _push_event then
## overwrote with the event kind, so the reward type was silently lost.
func test_kind_field_is_always_the_event_kind() -> void:
	var logger := GLog.new()
	logger.mirror_errors_to_engine = false
	logger.add_sink(Sinks.Memory.new())
	var s := Sim.new(Loader.load_rules(), 11, logger)
	s.player.hp = 1000000
	var bot := Bot.new()
	var seen := {}
	for t in 7200:
		s.step(bot.input(s))
		for ev in s.events:
			ok(typeof(ev["kind"]) == TYPE_INT and K.values().has(ev["kind"]), "kind overwritten: %s" % [ev])
			seen[ev["kind"]] = true
			if ev["kind"] == K.PICKUP or ev["kind"] == K.UPGRADE_SPAWNED:
				ok(ev.has("reward_kind") and ev["reward_kind"] in ["weapon", "tower", "heal", "armor", "maxhp", "frenzy", "speed"], "reward_kind missing: %s" % [ev])
	ok(seen.has(K.PICKUP) and seen.has(K.UPGRADE_SPAWNED), "2 sim-minutes produced pickups: %s" % [seen.keys().map(func(k): return Events.kind_name(k))])
