class_name Scoring
extends RefCounted
## Очки для лидерборда «Классика». Коэффициенты — в data/scoring.json.


static func compute(data: GameData, summary: Dictionary) -> int:
	var cfg: Dictionary = data.scoring
	var diff: Dictionary = data.difficulty(String(summary.get("difficulty", data.default_difficulty)))
	var cleared: int = int(summary.get("waves_cleared", 0))
	var points: float = 0.0
	for w: int in range(1, cleared + 1):
		points += float(cfg["per_wave_points"]) * float(w)
	points += float(cfg["perfect_wave_points"]) * float(summary.get("perfect_waves", 0))
	points += float(cfg["kill_points"]) * float(summary.get("kills", 0))
	points += float(cfg["life_points"]) * float(summary.get("lives", 0))
	if String(summary.get("outcome", "")) == "victory":
		var sb: Dictionary = cfg["speed_bonus"]
		var par: float = float(sb["par_seconds_per_wave"]) * float(summary.get("total_waves", cleared))
		var under: float = maxf(0.0, par - float(summary.get("combat_seconds", par)))
		points += under * float(sb["points_per_second_under_par"])
	return int(roundf(points * float(diff.get("score_mult", 1.0))))
