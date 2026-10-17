extends RefCounted
## Small synthesized cinematic cues; routed through Master, no external audio dependency.
static var cache: Dictionary = {}
static func cue(kind: String) -> AudioStreamWAV:
	if cache.has(kind):
		return cache[kind]
	var rate := 22050
	var length := 2.4 if kind == "impact" else 1.8
	var count := int(rate * length)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 84721
	var low := 0.0
	for i in count:
		var t := float(i) / rate
		var p := t / length
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.075)
		var value := 0.0
		match kind:
			"impact":
				value = (low * 2.0 + sin(TAU * (52.0 * t - 5.0 * t * t)) * 0.65) * exp(-t * 2.4) + noise * exp(-t * 25.0) * 0.35
			"meteor":
				value = (noise * 0.18 + low * 1.5 + sin(TAU * (180.0 * t + 90.0 * t * t)) * 0.12) * sin(PI * p) * p
			"portal":
				value = (sin(TAU * 65.0 * t) * 0.3 + sin(TAU * 98.0 * t) * 0.18 + low * 0.65) * sin(PI * p)
			_:
				value = (low * 1.5 + sin(TAU * (140.0 * t - 24.0 * t * t)) * 0.25) * exp(-t * 4.0)
		value *= minf(t / 0.008, 1.0) * minf((length - t) / 0.05, 1.0)
		bytes.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 28000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	cache[kind] = stream
	return stream
