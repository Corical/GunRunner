extends Node3D
## Feedback for sim events: particle bursts, floating text, hit flashes, camera shake/zoom.
## Everything is pooled and capped per frame, so a minigun into a crowd can never flood the screen or
## the frame time (the Babylon build crashed from uncapped effects, commit 11645b0).
## Runs on the view clock: paused game = frozen effects.

const Events = preload("res://scripts/sim/events.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const WorldView = preload("res://scripts/view/world_view.gd")
const K = Events.Kind

## Every event kind this presenter reacts to (test_events checks every kind is handled somewhere).
const HANDLED := [K.FIRED, K.ENEMY_HIT, K.ENEMY_KILLED, K.PLAYER_HURT, K.COMBO_BROKEN, K.ICE_HIT, K.ICE_SHATTERED,
	K.PICKUP, K.TOWER_DEPLOYED, K.BOSS_STARTED, K.BOSS_HIT, K.BOSS_CONTACT, K.BOSS_WRAPPED, K.BOSS_DEFEATED,
	K.GAME_OVER, K.POOL_EXHAUSTED, K.LEVEL_UP, K.PERK_TAKEN, K.EXPLOSION, K.CRIT, K.TRAP_HIT, K.TRAP_DESTROYED,
	K.TRAP_TRIGGERED]

const EMITTERS := 72  ## rocket trails add ~60 short-lived puffs per second
const LABELS := 40
const MAX_BURSTS_PER_FRAME := 8
const MAX_TEXTS_PER_FRAME := 6
const TEXT_LIFE := 0.9

var flash_requests: Array[int] = []  ## enemy serials to flash this frame; read and cleared by Actors

var _rules: Rules
var _camera: Camera3D
var _cam_base: Transform3D
var _cam_fov := 45.0
var _rng := RandomNumberGenerator.new()
var _emitters: Array[GPUParticles3D] = []
var _next_emitter := 0
var _labels: Array[Label3D] = []
var _label_age: Array[float] = []
var _label_rise: Array[float] = []
var _next_label := 0
var _shake := 0.0
var _shake_time := 0.0
var _zoom := 1.0
var _bursts_this_frame := 0
var _texts_this_frame := 0
var skipped := 0  ## effects dropped by the per-frame caps (telemetry)


func setup(rules: Rules, camera: Camera3D) -> void:
	_rules = rules
	_camera = camera
	_cam_base = camera.transform
	_cam_fov = camera.fov
	_rng.seed = 777
	var spark := SphereMesh.new()
	spark.radius = 0.12
	spark.height = 0.24
	spark.radial_segments = 6
	spark.rings = 3
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.material = spark_mat
	for i in EMITTERS:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.95
		p.lifetime = 0.6
		p.draw_pass_1 = spark
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ParticleProcessMaterial.new()
		m.direction = Vector3(0, 1, 0)
		m.spread = 180.0
		m.initial_velocity_min = 3.0
		m.initial_velocity_max = 7.0
		m.gravity = Vector3(0, -12, 0)
		m.scale_min = 0.6
		m.scale_max = 1.2
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 1))
		fade.set_color(1, Color(1, 1, 1, 0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = fade
		m.color_ramp = ramp
		p.process_material = m
		add_child(p)
		_emitters.append(p)
	for i in LABELS:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		# World-sized: numbers far down the road are small, near ones big (fixed size piled up at the horizon).
		l.fixed_size = false
		l.pixel_size = 0.02
		l.font_size = 40
		l.outline_size = 10
		l.render_priority = 20
		l.outline_render_priority = 19
		l.visible = false
		add_child(l)
		_labels.append(l)
		_label_age.append(TEXT_LIFE)
		_label_rise.append(0.0)


## Called once per frame with every event from the sim steps run this frame.
func handle(events: Array) -> void:
	for ev in events:
		match ev["kind"]:
			K.FIRED:
				_muzzle(ev)
			K.ENEMY_HIT:
				flash_requests.append(ev["serial"])
				_burst(ev, 0.0, 1.0, Color("#FFFFFF"), 6, 0.3, 4.0)
				_text(ev, "-%d" % ev["amount"], Color("#FFFFFF"), 1.0, 0.8)
			K.ENEMY_KILLED:
				var colour := Color(_rules.enemies[ev["enemy"]]["color"])
				_burst(ev, 0.0, 0.8, colour, 20, 0.6, 6.0)
				_text(ev, "+%d" % ev["score_gain"], Color("#FBBF24"), 1.5, 1.0)
			K.PLAYER_HURT:
				shake(0.6 if ev["source"] == "boss" else 0.3, 0.3)
			K.ICE_HIT:
				_burst(ev, 0.0, 1.0, Color("#A5F3FC"), 6, 0.35, 4.0)
			K.ICE_SHATTERED:
				_burst(ev, 0.0, 1.0, Color("#67E8F9"), 28, 0.7, 7.0)
			K.PICKUP:
				_burst(ev, 0.0, 1.0, Color("#FBBF24"), 24, 0.6, 5.0)
				_text(ev, _pickup_text(ev), Color("#FDE047"), 2.0, 1.3)
				zoom(0.92)
			K.TOWER_DEPLOYED:
				_burst(ev, 0.0, 1.0, Color(_rules.towers[ev["tower"]]["color"]), 24, 0.6, 5.0)
			K.BOSS_STARTED:
				shake(0.8, 0.6)
				_text({"x": 0.0, "z": 20.0}, "BOSS INCOMING!", Color("#F87171"), 5.0, 2.0, true)
			K.BOSS_HIT:
				_burst(ev, 0.0, 2.0, Color("#FCA5A5"), 6, 0.3, 4.0)
			K.BOSS_CONTACT:
				shake(0.9, 0.4)
			K.BOSS_WRAPPED:
				_text({"x": 0.0, "z": 15.0}, "IT'S COMING BACK!", Color("#F87171"), 4.0, 1.6, true)
			K.BOSS_DEFEATED:
				shake(1.0, 0.7)
				for i in 3:
					_burst(ev, (i - 1) * 1.5, 2.0 + i, Color("#DC2626") if i != 1 else Color("#FBBF24"), 32, 1.0, 9.0, true)
				_text(ev, "BOSS DEFEATED! +%d" % ev["score_gain"], Color("#FBBF24"), 5.0, 2.0, true)
			K.GAME_OVER:
				shake(1.0, 0.8)
			K.TRAP_HIT:
				_burst(ev, 0.0, 0.8, Color("#F87171"), 5, 0.3, 4.0)
			K.TRAP_DESTROYED:
				_burst(ev, 0.0, 0.8, Color("#7F1D1D"), 26, 0.6, 7.0)
				_text(ev, "CLEARED", Color("#FCA5A5"), 1.8, 1.0)
			K.TRAP_TRIGGERED:
				_burst(ev, 0.0, 1.0, Color("#DC2626"), 30, 0.7, 6.0)
				_text(ev, String(_rules.trap_by_id[ev["trap"]]["label"]).get_slice(" - ", 0) + "!", Color("#EF4444"), 2.6, 1.6, true)
				shake(0.35, 0.25)
			K.CRIT:
				# Corne 19:23: "a little smoke wherever you critical strike, with a number popping up".
				var at := WorldView.view_pos(float(ev["x"]), float(ev["z"]), 1.4)
				_emit(at, Color(0.85, 0.85, 0.88, 0.8), 8, 0.7, 1.2, 1.6, true)
				_emit(at, Color("#FDE047"), 14, 0.3, 6.0, 1.2, false)
				_text(ev, "%d!" % ev["amount"], Color("#FB923C"), 3.5, 1.6, true)
			K.EXPLOSION:
				_emit(WorldView.view_pos(float(ev["x"]), float(ev["z"]), 0.8), Color("#FB923C"), 40, 0.6, 9.0, 3.0, false)
				_emit(WorldView.view_pos(float(ev["x"]), float(ev["z"]), 1.2), Color(0.45, 0.45, 0.5, 0.8), 18, 1.2, 1.5, 2.5, true)
				_ring(ev, float(ev["radius"]))
				shake(0.35, 0.25)
			K.COMBO_BROKEN, K.POOL_EXHAUSTED, K.LEVEL_UP, K.PERK_TAKEN:
				pass  # shown by the HUD / level-up cards / logged; no world effect


## camera_base: where the camera is without shake this frame (the world view's follow camera).
func update(view_dt: float, camera_base: Transform3D) -> void:
	_cam_base = camera_base
	_update_rings(view_dt)
	_bursts_this_frame = 0
	_texts_this_frame = 0
	for i in _labels.size():
		if not _labels[i].visible:
			continue
		_label_age[i] += view_dt
		var life := TEXT_LIFE * (2.0 if _labels[i].font_size > 40 else 1.0)
		var t := _label_age[i] / life
		if t >= 1.0:
			_labels[i].visible = false
			continue
		_labels[i].position.y += _label_rise[i] * view_dt
		_labels[i].modulate.a = 1.0 - t * t
		_labels[i].outline_modulate.a = 1.0 - t * t
	_update_camera(view_dt)


## Shockwave: a flat ring growing to the real blast radius in 0.35 s and fading (pooled, 8 at once).
const RING_TIME := 0.35
var _rings: Array[MeshInstance3D] = []
var _ring_age: Array[float] = []
var _ring_radius: Array[float] = []
var _next_ring := 0


func _ring(ev: Dictionary, radius: float) -> void:
	if _rings.is_empty():
		var torus := TorusMesh.new()
		torus.inner_radius = 0.7
		torus.outer_radius = 1.0
		torus.rings = 24
		for i in 8:
			var mi := MeshInstance3D.new()
			mi.mesh = torus
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color("#FFE4B5")
			m.emission_enabled = true
			m.emission = Color("#FB923C")
			mi.material_override = m
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_rings.append(mi)
			_ring_age.append(RING_TIME)
			_ring_radius.append(1.0)
	var i := _next_ring
	_next_ring = (_next_ring + 1) % _rings.size()
	_rings[i].position = WorldView.view_pos(float(ev.get("x", 0.0)), float(ev.get("z", 0.0)), 0.3)
	_rings[i].visible = true
	_ring_age[i] = 0.0
	_ring_radius[i] = radius


func _update_rings(dt: float) -> void:
	for i in _rings.size():
		if not _rings[i].visible:
			continue
		_ring_age[i] += dt
		var t := _ring_age[i] / RING_TIME
		if t >= 1.0:
			_rings[i].visible = false
			continue
		var r := lerpf(0.3, _ring_radius[i], 1.0 - pow(1.0 - t, 3.0))
		_rings[i].scale = Vector3(r, 0.4, r)
		(_rings[i].material_override as StandardMaterial3D).albedo_color.a = 1.0 - t


func shake(intensity: float, seconds: float) -> void:
	if intensity >= _shake:
		_shake = intensity
		_shake_time = seconds


func zoom(fov_mult: float) -> void:
	_zoom = minf(_zoom, fov_mult)


func reset() -> void:
	_shake = 0.0
	_shake_time = 0.0
	_zoom = 1.0
	flash_requests.clear()
	for l in _labels:
		l.visible = false
	for p in _emitters:
		p.emitting = false
	if _camera != null:
		_camera.fov = _cam_fov


func _update_camera(dt: float) -> void:
	if _camera == null:
		return
	var offset := Vector3.ZERO
	if _shake_time > 0.0:
		_shake_time -= dt
		offset = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * _shake * 0.35
		if _shake_time <= 0.0:
			_shake = 0.0
	_camera.transform = _cam_base.translated_local(offset)
	_zoom = move_toward(_zoom, 1.0, dt * 0.4)
	_camera.fov = _cam_fov * _zoom


func _burst(ev: Dictionary, dx: float, y: float, colour: Color, amount: int, life: float, speed: float, force := false) -> void:
	if not force and _bursts_this_frame >= MAX_BURSTS_PER_FRAME:
		skipped += 1
		return
	_bursts_this_frame += 1
	_emit(WorldView.view_pos(float(ev.get("x", 0.0)) + dx, float(ev.get("z", 0.0)), y), colour, amount, life, speed, 1.0, false)


## size: particle scale multiplier; smoke: rises and drifts slowly instead of flying out and falling.
func _emit(pos: Vector3, colour: Color, amount: int, life: float, speed: float, size: float, smoke: bool) -> void:
	var p := _emitters[_next_emitter]
	_next_emitter = (_next_emitter + 1) % _emitters.size()
	p.amount = amount
	p.lifetime = life
	var m := p.process_material as ParticleProcessMaterial
	m.color = colour
	m.initial_velocity_min = speed * 0.5
	m.initial_velocity_max = speed
	m.scale_min = 0.6 * size
	m.scale_max = 1.2 * size
	m.gravity = Vector3(0, 1.5, 0) if smoke else Vector3(0, -12, 0)
	m.spread = 60.0 if smoke else 180.0
	p.position = pos
	p.restart()


## Per-gun muzzle effect: [flash colour, sparks, smoke puffs] (Corne 18:48: "a little smoke coming from the gun").
const MUZZLE := {
	"pistol": ["#FDE68A", 4, 0], "smg": ["#FDE68A", 3, 0], "minigun": ["#FEF3C7", 2, 0],
	"shotgun": ["#FB923C", 14, 5], "laser": ["#93C5FD", 5, 0], "rocket": ["#FB923C", 8, 8],
	"railgun": ["#C084FC", 16, 10], "flamethrower": ["#000000", 0, 0], "grenade": ["#BEF264", 5, 4],
}


func _muzzle(ev: Dictionary) -> void:
	var spec: Array = MUZZLE.get(ev["weapon"], ["#FDE68A", 3, 0])
	var at := WorldView.view_pos(float(ev["x"]), float(ev["z"]) + 1.2, 1.1)
	if spec[1] > 0:
		_emit(at, Color(spec[0]), spec[1], 0.15, 3.0, 1.0, false)
	if spec[2] > 0:
		_emit(at, Color(0.75, 0.75, 0.78, 0.7), spec[2], 0.9, 0.8, 1.6, true)


## Burning / poisoned enemies: small rising flames or green bubbles, 8 puffs a second per enemy.
var _status_last := {}


func status_puff(serial: int, pos: Vector3, status: String, now: float) -> void:
	if now - float(_status_last.get(serial, -1.0)) < 0.07:
		return
	_status_last[serial] = now
	if _status_last.size() > 128:
		_status_last.clear()
	if status == "burn":
		_emit(pos, Color("#FDBA74"), 7, 0.5, 2.2, 2.0, true)
	else:
		_emit(pos, Color("#4ADE80"), 4, 0.8, 1.0, 1.4, true)


## Rocket smoke trail: a few slow grey puffs every 0.05 s per rocket (called by the actor view per frame).
var _trail_last := {}


func trail(serial: int, pos: Vector3, now: float) -> void:
	if now - float(_trail_last.get(serial, -1.0)) < 0.05:
		return
	_trail_last[serial] = now
	if _trail_last.size() > 64:
		_trail_last.clear()
	_emit(pos, Color(0.7, 0.7, 0.72, 0.6), 3, 0.8, 0.4, 1.4, true)


func _text(ev: Dictionary, text: String, colour: Color, y: float, rise: float, big := false) -> void:
	if not big and _texts_this_frame >= MAX_TEXTS_PER_FRAME:
		skipped += 1
		return
	_texts_this_frame += 1
	var l := _labels[_next_label]
	var i := _next_label
	_next_label = (_next_label + 1) % _labels.size()
	l.text = text
	l.font_size = 72 if big else 40
	l.modulate = colour
	l.outline_modulate = Color(0, 0, 0, 1)
	l.position = WorldView.view_pos(float(ev.get("x", 0.0)), float(ev.get("z", 0.0)), y)
	l.visible = true
	_label_age[i] = 0.0
	_label_rise[i] = rise


func _pickup_text(ev: Dictionary) -> String:
	var id: String = ev["reward"]
	if _rules.weapons.has(id):
		return String(_rules.weapons[id]["name"]).to_upper() + "!"
	if _rules.towers.has(id):
		return String(_rules.towers[id]["name"]).to_upper() + "!"
	match id:
		"heal":
			return "+%d HP" % _rules.t("heal_amount")
		"armor":
			return "+%d ARMOUR" % _rules.t("armor_amount")
		"maxhp":
			return "MAX HP UP!"
		"frenzy":
			return "FRENZY %ds!" % _rules.t("frenzy_seconds")
		"speed":
			return "FIRE RATE %ds!" % _rules.t("speed_buff_seconds")
	return id.to_upper()
