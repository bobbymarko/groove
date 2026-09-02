class_name RideMetrics
extends RefCounted
## Summary numbers for a ride from its 1 Hz samples.

## Returns {duration_s, avg_power, max_power, normalized_power, intensity_factor,
## tss, kj, avg_heart_rate, max_heart_rate, avg_cadence, distance_m}.
static func compute(samples: Array, ftp: int) -> Dictionary:
	var n := samples.size()
	if n == 0:
		return {"duration_s": 0, "avg_power": 0, "max_power": 0, "normalized_power": 0,
			"intensity_factor": 0.0, "tss": 0.0, "kj": 0.0, "avg_heart_rate": 0,
			"max_heart_rate": 0, "avg_cadence": 0, "distance_m": 0.0}
	var sum_p := 0
	var max_p := 0
	var sum_h := 0
	var n_h := 0
	var max_h := 0
	var sum_c := 0
	var n_c := 0
	var dist := 0.0
	for s in samples:
		var p := int(s.get("p", 0))
		sum_p += p
		max_p = maxi(max_p, p)
		var h := int(s.get("h", 0))
		if h > 0:
			sum_h += h
			n_h += 1
			max_h = maxi(max_h, h)
		var c := int(s.get("c", 0))
		if c > 0:
			sum_c += c
			n_c += 1
		dist += float(s.get("v", 0.0)) / 3.6
	var avg_p := float(sum_p) / n
	var np := normalized_power(samples)
	var intensity := np / ftp if ftp > 0 else 0.0
	var tss := (n * np * intensity) / (ftp * 3600.0) * 100.0 if ftp > 0 else 0.0
	return {
		"duration_s": n,
		"avg_power": int(round(avg_p)),
		"max_power": max_p,
		"normalized_power": int(round(np)),
		"intensity_factor": intensity,
		"tss": tss,
		"kj": sum_p / 1000.0,
		"avg_heart_rate": int(round(float(sum_h) / n_h)) if n_h > 0 else 0,
		"max_heart_rate": max_h,
		"avg_cadence": int(round(float(sum_c) / n_c)) if n_c > 0 else 0,
		"distance_m": dist,
	}


## Coggan normalized power: 30 s rolling average, fourth power, mean, fourth root.
## Rides shorter than 30 s fall back to average power.
static func normalized_power(samples: Array) -> float:
	var n := samples.size()
	if n == 0:
		return 0.0
	if n < 30:
		var sum := 0.0
		for s in samples:
			sum += float(s.get("p", 0))
		return sum / n
	var window := 0.0
	var acc := 0.0
	var count := 0
	for i in n:
		window += float(samples[i].get("p", 0))
		if i >= 30:
			window -= float(samples[i - 30].get("p", 0))
		if i >= 29:
			var avg := window / 30.0
			acc += pow(avg, 4)
			count += 1
	return pow(acc / count, 0.25)
