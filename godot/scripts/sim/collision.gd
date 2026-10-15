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


static func dist_sq(ax: float, az: float, bx: float, bz: float) -> float:
	return (ax - bx) * (ax - bx) + (az - bz) * (az - bz)
