extends RefCounted
## Port: where 3D models come from. The view asks for a model by kind + id and never knows whether it gets a
## stand-in built from primitives or an imported glTF. Every model's origin is on the ground at its centre,
## facing the player (toward -z).
##
## kinds: "player", "enemy", "boss", "weapon", "tower", "reward", "ice", "trap"
## ids:   enemy/weapon/tower ids from data/*.tsv; reward ids from rewards.tsv; "" for player/boss/ice

const KINDS := ["player", "enemy", "boss", "weapon", "tower", "reward", "ice", "trap"]


## A new, independent node tree each call (callers pool them).
func make(kind: String, id: String) -> Node3D:
	push_error("ModelCatalog.make not implemented by %s" % get_script().resource_path)
	assert(false)
	return Node3D.new()


## Where bullets leave a weapon model, in the model's local space.
func muzzle(weapon_id: String) -> Vector3:
	push_error("ModelCatalog.muzzle not implemented by %s" % get_script().resource_path)
	assert(false)
	return Vector3.ZERO


## True when this catalog draws stand-ins, so the HUD can say so.
func is_stand_in() -> bool:
	return true
