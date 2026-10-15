extends RefCounted
## Turns real frame time into a whole number of fixed sim steps.
## - speed multiplier = more (or fewer) steps per frame, never a bigger step (plan D9)
## - at most max_steps per frame; the rest is dropped, not carried, so a long stall can't snowball
## - while paused nothing accumulates, so resuming never bursts

const STEP := 1.0 / 60.0
## Absorbs float error so 60 frames of 1/60 s are exactly 60 steps.
const EPSILON := 1e-9

## ours, unmeasured: 3x speed at 30 fps needs 6 steps per frame; 12 leaves headroom.
var max_steps := 12
var speed := 1.0
var paused := false
var dropped_steps := 0

var _acc := 0.0


## Returns how many sim steps to run for a frame that took real_dt seconds.
func advance(real_dt: float) -> int:
	if paused or is_nan(real_dt) or is_inf(real_dt) or real_dt <= 0.0:
		return 0
	_acc += real_dt * speed
	var n := int(floor(_acc / STEP + EPSILON))
	_acc = maxf(0.0, _acc - n * STEP)
	if n > max_steps:
		dropped_steps += n - max_steps
		n = max_steps
	return n


func set_speed(multiplier: float) -> void:
	speed = clampf(multiplier, 0.3, 3.0)
