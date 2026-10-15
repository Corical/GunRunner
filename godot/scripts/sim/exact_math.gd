extends RefCounted
## Maths the sim may use when a result must be identical on every platform. Only +, -, *, / and abs, which
## IEEE 754 defines exactly. sin()/pow() come from each platform's C library, and Windows and Android do not
## promise the same last digit (Fable review #4) - so a run recorded on the phone could fail to replay on the PC.


## A smooth side-to-side wave in -1..1 with period TAU, shaped like sin (slows at the edges), but exact.
## Triangle wave, then the cubic 1.5t - 0.5t^3 rounds off its corners (zero slope at +-1).
static func wave(phase: float) -> float:
	var p := fposmod(phase, TAU) / TAU
	var tri := 4.0 * p - 1.0 if p < 0.5 else 3.0 - 4.0 * p
	return 1.5 * tri - 0.5 * tri * tri * tri


## base^n for whole n >= 0 by repeated multiplication (exact steps, unlike pow()).
static func int_power(base: float, n: int) -> float:
	var out := 1.0
	for i in maxi(0, n):
		out *= base
	return out
