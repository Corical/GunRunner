extends Node3D
## Draws everything the sim has in play: player, enemies, bullets, frozen upgrades, towers, boss.
## Reads sim state every frame and draws it between the last two sim steps (alpha), so motion is smooth
## on any refresh rate. One view slot per sim pool slot; models come from the ModelCatalog port and are
## built once per slot per type, then reused.

const Sim = preload("res://scripts/sim/sim.gd")
const ModelCatalog = preload("res://scripts/ports/model_catalog.gd")
const WorldView = preload("res://scripts/view/world_view.gd")

const BAR_WIDTH := 1.4


class Slot:
	extends RefCounted
	var root: Node3D
	var models := {}       ## id -> Node3D
	var current := ""
	var bar_bg: MeshInstance3D
	var bar_fill: MeshInstance3D
	var extra: Node3D      ## ice block for upgrades
	var status := ""       ## "", "burn", "poison": overlay currently applied


var _sim: Sim
var _catalog: ModelCatalog
var _t := 0.0

## Effects presenter, for rocket smoke trails (set by play_mode; null in tests).
var juice: Node3D

## Telemetry: models built since last read, and the time spent building them.
var models_built := 0
var build_usec := 0
var prewarm_ms := 0.0

const LEAN_RADIANS := 0.35  ## ours: full lean at drag top speed

var _player: Node3D
var _player_body: Node3D
var _player_model: Node3D
var _player_weapon: Node3D
var _blob_mesh: QuadMesh
var _blob_mat: StandardMaterial3D
var _player_weapon_id := ""
var _enemies: Array[Slot] = []
var _upgrades: Array[Slot] = []
var _traps: Array[Slot] = []
var _towers: Array[Slot] = []
var _boss: Node3D
var _bullets: MultiMeshInstance3D
var _flash_mat: StandardMaterial3D
var _burn_mat: StandardMaterial3D
var _poison_mat: StandardMaterial3D
var _flash_left := {}  ## enemy slot index -> seconds of white flash left
var _bar_bg_mat: StandardMaterial3D
var _bar_fill_mat: StandardMaterial3D
var _ice_bar_mat: StandardMaterial3D


func setup(catalog: ModelCatalog, sim: Sim) -> void:
	_catalog = catalog
	_blob_build()
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 1, 1, 0.75)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_burn_mat = _flash_mat.duplicate()
	_burn_mat.albedo_color = Color(1.0, 0.62, 0.05, 0.8)  # strong: orange on red enemies barely showed at 0.55
	_poison_mat = _flash_mat.duplicate()
	_poison_mat.albedo_color = Color(0.2, 1.0, 0.25, 0.78)  # strong: at 0.5 red+green read as yellow
	_bar_bg_mat = _bar_mat(Color(0.1, 0.1, 0.1, 0.8))
	_bar_fill_mat = _bar_mat(Color("#EF4444"))
	_ice_bar_mat = _bar_mat(Color("#67E8F9"))
	# Player = root (position) > body (lean + bob) > model; the blob shadow stays on the ground under the root.
	_player = Node3D.new()
	add_child(_player)
	_player.add_child(_blob(1.0))
	_player_body = Node3D.new()
	_player.add_child(_player_body)
	var model := catalog.make("player", "")
	model.rotation.y = PI  # face the enemies
	_player_body.add_child(model)
	_player_model = model
	for i in sim.enemies.pool.size():
		var es := _new_slot(true, _bar_fill_mat)
		es.root.add_child(_blob(1.1))
		_enemies.append(es)
	for i in sim.upgrades.pool.size():
		var s := _new_slot(true, _ice_bar_mat)
		s.extra = catalog.make("ice", "")
		s.root.add_child(s.extra)
		_upgrades.append(s)
	for i in sim.traps.pool.size():
		_traps.append(_new_slot(true, _bar_fill_mat))
	for i in sim.towers.pool.size():
		_towers.append(_new_slot(false, null))
	_boss = catalog.make("boss", "")
	_boss.visible = false
	_boss.add_child(_blob(4.5))
	add_child(_boss)
	_bullets_build(sim.bullets.pool.size())
	_prewarm(sim)
	bind(sim)


## Build every model the game can show once, at start-up, so nothing is created (and no new material or
## mesh reaches the GPU for the first time) in the middle of a run. Enemy slots get every enemy type;
## upgrade slots every reward; tower slots every tower. All hidden until the sim uses them.
func _prewarm(sim: Sim) -> void:
	var started := Time.get_ticks_usec()
	for s in _enemies:
		for id in sim.rules.enemy_ids:
			_show_model(s, "enemy", id)
	for s in _upgrades:
		for row in sim.rules.rewards:
			_show_model(s, "reward", row["id"])
	for s in _traps:
		for row in sim.rules.traps:
			_show_model(s, "trap", row["id"])
	for s in _towers:
		for id in sim.rules.towers:
			_show_model(s, "tower", id)
	for s in _enemies + _upgrades + _towers + _traps:
		s.models[s.current].visible = false
		s.current = ""
	prewarm_ms = (Time.get_ticks_usec() - started) / 1000.0
	models_built = 0
	build_usec = 0


## Point the views at a new game (restart). Hides everything until the sim says it is active.
func bind(sim: Sim) -> void:
	_sim = sim
	_player_weapon_id = ""
	for i in _flash_left.keys():
		_set_overlay(_enemies[i], null)
	_flash_left.clear()
	for s in _enemies + _upgrades + _towers + _traps:
		s.root.visible = false
	_boss.visible = false


## White flash on enemies hit this frame (serials from the juice presenter), 0.1 s on the view clock.
func flash(serials: Array[int], view_dt: float) -> void:
	for serial in serials:
		for i in _enemies.size():
			if _sim.enemies.pool[i].active and _sim.enemies.pool[i].serial == serial:
				if not _flash_left.has(i):
					_set_overlay(_enemies[i], _flash_mat)
				_flash_left[i] = 0.1
	serials.clear()
	for i in _flash_left.keys():
		_flash_left[i] -= view_dt
		if _flash_left[i] <= 0.0 or not _sim.enemies.pool[i].active:
			_set_overlay(_enemies[i], null)
			_enemies[i].status = ""  # status tint is re-applied next frame if still burning/poisoned
			_flash_left.erase(i)


## Setting applies to the slot's current model; clearing (mat = null) wipes every model in the slot, because the
## slot may have switched enemy type while the flash was running.
func _set_overlay(s: Slot, mat: Material) -> void:
	var targets: Array = s.models.values() if mat == null else ([s.models[s.current]] if s.models.has(s.current) else [])
	for model in targets:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = mat


func sync(alpha: float, view_dt: float) -> void:
	_t += view_dt
	_sync_player(alpha)
	_sync_enemies(alpha)
	_sync_bullets(alpha)
	_sync_upgrades(alpha)
	_sync_traps(alpha)
	_sync_towers()
	_sync_boss(alpha)


func _sync_player(alpha: float) -> void:
	var p := _sim.player
	_player.position = WorldView.view_pos(lerpf(p.prev_x, p.x, alpha), p.z)
	# Lean into sideways speed and bob while running (view only; the sim position is untouched).
	_player_body.rotation.z = clampf(p.vx / _sim.rules.t("player_drag_max_speed"), -1.0, 1.0) * LEAN_RADIANS
	_player_body.position.y = absf(sin(_t * 14.0)) * 0.12
	if p.weapon_id != _player_weapon_id:
		if _player_weapon != null:
			_player_weapon.queue_free()
		_player_weapon = _catalog.make("weapon", p.weapon_id)
		_player_weapon.position = Vector3(-0.45, 1.0, -0.4)  # in the player's (turned-around) hands
		_player_model.add_child(_player_weapon)
		_player_weapon_id = p.weapon_id


func _sync_enemies(alpha: float) -> void:
	for i in _enemies.size():
		var e = _sim.enemies.pool[i]
		var s := _enemies[i]
		if not e.active:
			s.root.visible = false
			continue
		_show_model(s, "enemy", e.type_id)
		s.root.visible = true
		s.root.position = WorldView.view_pos(lerpf(e.prev_x, e.x, alpha), lerpf(e.prev_z, e.z, alpha))
		s.models[s.current].position.y = absf(sin(_t * 11.0 + e.serial * 1.7)) * 0.15  # run bob, out of step
		# Status look (Corne 18:52: "at least look like it's on fire... or poison"): tint + rising flames/bubbles.
		var status := "burn" if e.burning else ("poison" if e.poison_timer > 0.0 else "")
		if status != s.status and not _flash_left.has(i):
			_set_overlay(s, null)
			if status != "":
				_set_overlay(s, _burn_mat if status == "burn" else _poison_mat)
			s.status = status
		if status != "" and juice != null:
			juice.status_puff(e.serial, s.root.position + Vector3(0, float(e.row["size"]) * 1.2, 0), status, _t)
		_set_bar(s, float(e.hp) / e.max_hp, e.max_hp > 1, float(e.row["size"]) * 1.4 + 1.0)


## Telemetry for "invisible enemies" (Corne 17:50): sim enemies active vs enemy models actually shown,
## and active enemies whose model is not visible this frame. Must match every frame.
func drawn_counts() -> Dictionary:
	var active := 0
	var drawn := 0
	var hidden_active: PackedStringArray = []
	for i in _enemies.size():
		var e = _sim.enemies.pool[i]
		if not e.active:
			continue
		active += 1
		var s := _enemies[i]
		var shown: bool = s.root.visible and s.models.has(s.current) and s.models[s.current].visible and s.current == e.type_id
		if shown:
			drawn += 1
		elif hidden_active.size() < 5:
			hidden_active.append("%s slot%d root=%s current=%s" % [e.type_id, i, s.root.visible, s.current])
	return {"active": active, "drawn": drawn, "hidden": ";".join(hidden_active)}


func _sync_bullets(alpha: float) -> void:
	var mm := _bullets.multimesh
	var n := 0
	for b in _sim.bullets.pool:
		if not b.active:
			continue
		var look: Array = _bullet_look(b.weapon_id)
		var size: float = look[0]
		var z := lerpf(b.prev_z, b.z, alpha)
		var t := clampf((z - b.start_z) / maxf(1.0, b.max_range), 0.0, 1.0)  # 0 at the muzzle, 1 at max range
		var y: float = 1.0 + look[3] * 4.0 * t * (1.0 - t)  # bullet_arc: lobbed up and down over the range
		var stretch: float = look[2]
		var grow: float = 1.0 + look[4] * t  # bullet_grow: flame cone widens
		var pos := WorldView.view_pos(lerpf(b.prev_x, b.x, alpha), z, y)
		if look[5] and juice != null:
			juice.trail(b.serial, pos, _t)
		var s := size * grow
		mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s, s, s * stretch)), pos))
		mm.set_instance_color(n, look[1])
		n += 1
	mm.visible_instance_count = n


var _bullet_looks := {}  ## weapon id -> [size, Color, stretch, arc, grow, trail]; parsed once, not per bullet per frame (Fable #13)


func _bullet_look(weapon_id: String) -> Array:
	if not _bullet_looks.has(weapon_id):
		var w: Dictionary = _sim.rules.weapons[weapon_id]
		var lk: Dictionary = _sim.rules.weapon_looks[weapon_id]
		_bullet_looks[weapon_id] = [float(w["bullet_size"]), Color(w["bullet_color"]), float(lk["bullet_stretch"]),
			float(lk["bullet_arc"]), float(lk["bullet_grow"]), int(lk["smoke_trail"]) == 1]
	return _bullet_looks[weapon_id]


func _sync_upgrades(alpha: float) -> void:
	for i in _upgrades.size():
		var u = _sim.upgrades.pool[i]
		var s := _upgrades[i]
		if not u.active:
			s.root.visible = false
			continue
		_show_model(s, "reward", u.reward_id)
		s.root.visible = true
		s.root.position = WorldView.view_pos(lerpf(u.prev_x, u.x, alpha), lerpf(u.prev_z, u.z, alpha))
		s.extra.visible = not u.thawed
		var reward: Node3D = s.models[u.reward_id]
		if u.thawed:
			reward.position.y = 0.3 + sin(_t * 5.0) * 0.25
			reward.rotation.y = _t * 2.0
		else:
			reward.position.y = 0.0
			reward.rotation.y = 0.0
		var full := int(_sim.rules.t("upgrade_ice_hp"))
		_set_bar(s, float(u.ice_hp) / full, not u.thawed, 2.6)


func _sync_traps(alpha: float) -> void:
	for i in _traps.size():
		var t = _sim.traps.pool[i]
		var s := _traps[i]
		if not t.active:
			s.root.visible = false
			continue
		_show_model(s, "trap", t.trap_id)
		s.root.visible = true
		s.root.position = WorldView.view_pos(lerpf(t.prev_x, t.x, alpha), lerpf(t.prev_z, t.z, alpha))
		s.models[t.trap_id].rotation.y = _t * 1.5
		var full := int(_sim.rules.t("trap_hp"))
		_set_bar(s, float(t.hp) / full, t.hp < full, 2.0)


func _sync_towers() -> void:
	for i in _towers.size():
		var t = _sim.towers.pool[i]
		var s := _towers[i]
		if not t.active:
			s.root.visible = false
			continue
		_show_model(s, "tower", t.type_id)
		s.root.position = WorldView.view_pos(t.x, t.z)
		# Blink in the last 3 seconds so the player sees it is about to go.
		s.root.visible = t.time_left > 3.0 or fmod(_t, 0.4) < 0.25
		var model: Node3D = s.models[t.type_id]
		var top := model.get_node_or_null("Top") as Node3D
		if top != null:
			top.rotation.y = _t * 2.0
		var disc := model.get_node_or_null("Range") as Node3D
		if disc != null:
			var pulse := 1.0 + sin(_t * 3.0) * 0.03
			disc.scale = Vector3(pulse, 1.0, pulse)


func _sync_boss(alpha: float) -> void:
	var b := _sim.boss
	_boss.visible = b.active
	if not b.active:
		return
	var x := lerpf(b.prev_x, b.x, alpha) + sin(_t * 1.5) * 0.5
	_boss.position = WorldView.view_pos(x, lerpf(b.prev_z, b.z, alpha), absf(sin(_t * 2.0)) * 0.3)


# ---------- helpers ----------

## Soft dark disc on the ground: grounding for characters without real shadows (too costly on the Iris Xe).
func _blob_build() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.45))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_blob_mat = StandardMaterial3D.new()
	_blob_mat.albedo_texture = tex
	_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blob_mesh = QuadMesh.new()
	_blob_mesh.size = Vector2(2, 2)
	_blob_mesh.orientation = PlaneMesh.FACE_Y


func _blob(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _blob_mesh
	mi.material_override = _blob_mat
	mi.scale = Vector3(radius, 1, radius)
	mi.position.y = 0.03
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _new_slot(with_bar: bool, fill_mat: StandardMaterial3D) -> Slot:
	var s := Slot.new()
	s.root = Node3D.new()
	s.root.visible = false
	add_child(s.root)
	if with_bar:
		s.bar_bg = _bar_quad(Vector2(BAR_WIDTH + 0.1, 0.18), Vector3.ZERO, _bar_bg_mat)
		s.bar_fill = _bar_quad(Vector2(BAR_WIDTH, 0.12), Vector3(BAR_WIDTH / 2.0, 0, 0), fill_mat)
		s.root.add_child(s.bar_bg)
		s.root.add_child(s.bar_fill)
	return s


func _show_model(s: Slot, kind: String, id: String) -> void:
	if s.current == id:
		return
	if s.current != "" and s.models.has(s.current):
		s.models[s.current].visible = false
	if not s.models.has(id):
		var started := Time.get_ticks_usec()
		var m := _catalog.make(kind, id)
		s.root.add_child(m)
		s.models[id] = m
		models_built += 1
		build_usec += Time.get_ticks_usec() - started
	s.models[id].visible = true
	s.current = id


## The fill quad grows from its left edge. Screen-left is world +x (camera looks down +z).
func _set_bar(s: Slot, ratio: float, show: bool, height: float) -> void:
	s.bar_bg.visible = show
	s.bar_fill.visible = show
	if not show:
		return
	s.bar_bg.position = Vector3(0, height, 0)
	s.bar_fill.position = Vector3(BAR_WIDTH / 2.0, height, -0.01)
	s.bar_fill.scale = Vector3(clampf(ratio, 0.0, 1.0), 1, 1)


func _bar_quad(size: Vector2, offset: Vector3, mat: Material) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = offset
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _bar_mat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true  # the fill bar shrinks by scale
	m.no_depth_test = true
	m.render_priority = 10
	if colour.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _bullets_build(count: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mm.mesh = sphere
	mm.instance_count = count
	mm.visible_instance_count = 0
	_bullets = MultiMeshInstance3D.new()
	_bullets.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bullets.material_override = m
	_bullets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bullets)
