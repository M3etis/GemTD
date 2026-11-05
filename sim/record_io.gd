class_name RecordIO
extends RefCounted
## Записи лидерборда: сборка из итогов забега, экспорт и проверяемый импорт (§10.4 PROMPT.md).

const EXPORT_FORMAT: String = "gtdx"
const EXPORT_VERSION: int = 1
## Поля записи, которые при импорте берутся из файла (остальное пересчитывается ресимуляцией).
const TRUSTED_FIELDS: Array[String] = ["id", "name", "date", "daily", "real_seconds", "version", "profile", "mode",
	"place", "players", "opponents", "match_seed"]


static func record_from_summary(data: GameData, summary: Dictionary, base: Dictionary) -> Dictionary:
	var rec: Dictionary = base.duplicate(true)
	rec.merge({
		"difficulty": summary["difficulty"],
		"seed": summary["seed"],
		"outcome": summary["outcome"],
		"waves_cleared": summary["waves_cleared"],
		"total_waves": summary["total_waves"],
		"kills": summary["kills"],
		"leaks": summary["leaks"],
		"lives": summary["lives"],
		"perfect_waves": summary["perfect_waves"],
		"score": Scoring.compute(data, summary),
		"combat_seconds": snappedf(float(summary["combat_seconds"]), 0.01),
		"total_damage": summary["total_damage"],
		"peak_dps": summary["peak_dps"],
		"best_tower": summary["best_tower"],
		"gems_used": summary["gems_used"],
		"specials": summary.get("specials", {}),
		"damage_dps": int(summary.get("damage_test_dps", 0)),
		"damage_total": int(summary.get("damage_test_damage", 0)),
		"data_hash": data.data_hash,
		"verified": false,
		"verify_state": "pending",
	}, true)
	return rec


static func export_bundle(rec: Dictionary, replay: Dictionary) -> Dictionary:
	var clean: Dictionary = rec.duplicate(true)
	clean.erase("replay")
	clean.erase("verify_reason")
	return {"format": EXPORT_FORMAT, "format_version": EXPORT_VERSION, "record": clean, "replay": replay}


## {ok, reason, record, replay}. Подделанные очки/волны не пройдут: запись пересчитывается из реплея.
static func import_bundle(data: GameData, bundle: Dictionary) -> Dictionary:
	if String(bundle.get("format", "")) != EXPORT_FORMAT or not (bundle.get("record") is Dictionary) or not (bundle.get("replay") is Dictionary):
		return {"ok": false, "reason": "ERR_IMPORT_FORMAT"}
	var replay: Dictionary = bundle["replay"]
	var sim_res: Dictionary = Replay.simulate(data, replay)
	if not sim_res["ok"]:
		return {"ok": false, "reason": String(sim_res["reason"])}
	var sim: GameSim = sim_res["sim"]
	if not sim.is_over():
		return {"ok": false, "reason": "ERR_IMPORT_UNFINISHED"}
	var src: Dictionary = bundle["record"]
	var base: Dictionary = {}
	for key: String in TRUSTED_FIELDS:
		if src.has(key):
			base[key] = src[key]
	if not base.has("id") or String(base["id"]).is_empty():
		return {"ok": false, "reason": "ERR_IMPORT_FORMAT"}
	base["name"] = NetProtocol.sanitize_name(String(base.get("name", "")))
	base["imported"] = true
	var rec: Dictionary = record_from_summary(data, sim.summary(), base)
	rec["verified"] = true
	rec["verify_state"] = "ok"
	return {"ok": true, "reason": "", "record": rec, "replay": replay}
