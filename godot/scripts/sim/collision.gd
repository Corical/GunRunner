extends RefCounted
## Swept circle tests on the x/z plane. A bullet is a moving point; a target is a moving circle.
## Testing the relative motion over the whole step means no target can be skipped, whatever the speed.


## True if a point moving from (ax, az) to (bx, bz) passes strictly inside a circle of radius r at the origin.
static func segment_hits_origin(ax: float, az: float, bx: float, bz: float, r: float) -> bool:
	var dx := bx - ax
	var dz := bz - az
	var len_sq := dx * dx + dz * dz
	var t := 0.0
	if len_sq > 0.0:
		t = clampf(-(ax * dx + az * dz) / len_sq, 0.0, 1.0)
	var px := ax + t * dx
	var pz := az + t * dz
	return px * px + pz * pz < r * r


## Point (bullet) moved prev->cur while the circle's centre moved cprev->ccur during the same step.
static func swept_hit(
	b_prev_x: float, b_prev_z: float, b_x: float, b_z: float,
	c_prev_x: float, c_prev_z: float, c_x: float, c_z: float, r: float
) -> bool:
	return segment_hits_origin(b_prev_x - c_prev_x, b_prev_z - c_prev_z, b_x - c_x, b_z - c_z, r)


## Like swept_hit, but returns how far along the step (0..1) the point first enters the circle, or -1 on a miss.
## Used to resolve several hits in one step in path order (Fable review #3: pool-slot order let an enemy
## behind take the hit meant for the one in front). A hit here is exactly a hit in swept_hit.
static func swept_entry(
	b_prev_x: float, b_prev_z: float, b_x: float, b_z: float,
	c_prev_x: float, c_prev_z: float, c_x: float, c_z: float, r: float
) -> float:
	var ax := b_prev_x - c_prev_x
	var az := b_prev_z - c_prev_z
	if not segment_hits_origin(ax, az, b_x - c_x, b_z - c_z, r):
		return -1.0
	var dx := (b_x - c_x) - ax
	var dz := (b_z - c_z) - az
	var dd := dx * dx + dz * dz
	var c := ax * ax + az * az - r * r
	if c < 0.0 or dd == 0.0:
		return 0.0  # already inside at the start of the step
	var half_b := ax * dx + az * dz
	var disc := half_b * half_b - dd * c
	return clampf((-half_b - sqrt(maxf(disc, 0.0))) / dd, 0.0, 1.0)


## Cheap exact pre-check for swept_hit / swept_entry: false when this step's z or x extents of the two movers are
## further apart than r, in which case the swept test is false too (both move in straight lines over the step).
static func extents_overlap(
	b_prev_x: float, b_prev_z: float, b_x: float, b_z: float,
	c_prev_x: float, c_prev_z: float, c_x: float, c_z: float, r: float
) -> bool:
	if minf(c_prev_z, c_z) - r > maxf(b_prev_z, b_z) or maxf(c_prev_z, c_z) + r < minf(b_prev_z, b_z):
		return false
	return not (minf(c_prev_x, c_x) - r > maxf(b_prev_x, b_x) or maxf(c_prev_x, c_x) + r < minf(b_prev_x, b_x))


static func dist_sq(ax: float, az: float, bx: float, bz: float) -> float:
	return (ax - bx) * (ax - bx) + (az - bz) * (az - bz)
