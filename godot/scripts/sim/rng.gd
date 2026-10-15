extends RefCounted
## The sim's only source of randomness. Seeded once per run; never shared with the view
## (shake, particles and trees use their own generator so rendering can't change gameplay).

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


## Uniform in [0, 1].
func next_float() -> float:
	return _rng.randf()


func range_float(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## Inclusive on both ends.
func range_int(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Internal generator state, for determinism hashes.
func state() -> int:
	return _rng.state
