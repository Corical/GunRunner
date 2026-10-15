extends SceneTree
## Prints the bounding box of every .glb under res://assets/models (size and centre), so the catalog can scale and
## turn them. Run: godot --headless --path godot --script res://tools/measure_models.gd


func _init() -> void:
	for dir in ["res://assets/models/kenney_blaster"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".glb"):
				continue
			var scene: Node3D = (load(dir.path_join(f)) as PackedScene).instantiate()
			var box := _bounds(scene, Transform3D.IDENTITY)
			print("%s size=%s centre=%s" % [f, box.size, box.get_center()])
			scene.free()
	quit()


func _bounds(n: Node, parent: Transform3D) -> AABB:
	var xf := parent
	if n is Node3D:
		xf = parent * (n as Node3D).transform
	var box := AABB()
	var first := true
	if n is MeshInstance3D:
		box = xf * (n as MeshInstance3D).get_aabb()
		first = false
	for c in n.get_children():
		var b := _bounds(c, xf)
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return box
