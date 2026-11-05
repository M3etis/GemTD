class_name GamePresenter
extends RefCounted
## Реакция на события симуляции: звук, частицы, тряска камеры, журнал, баннеры.
## Не меняет состояние игры — только «подача».

const T := preload("res://ui/theme/ui_tokens.gd")

var data: GameData
var sim: GameSim
var board: BoardView
var fx: FxLayer
var cam: CameraRig
var hud: Hud
var flash: float = 0.0
var aberration: float = 0.0
## Затемнение экрана при появлении босса (0..1, гаснет само).
var darken: float = 0.0
## Замедление времени при раскрытии гема IV–V (в «Гонке» выключено).
var allow_slowmo: bool = true
var _coin_next_ms: int = 0
## Наблюдение за чужим полем: без записей в журнал, баннеров и вспышек потери жизни.
var quiet_ui: bool = false
## Цвет подписи заблокированного удара по трейту.
const BLOCK_COLORS: Dictionary = {
	"antimagic": Color("9db8ff"), "ethereal": Color("d7c8ff"), "evasion": Color("e8f0ff"),
	"refraction": Color("9fe8ff"), "carapace": Color("e8b87a"),
}


func _init(d: GameData, s: GameSim, b: BoardView, f: FxLayer, c: CameraRig, h: Hud) -> void:
	data = d
	sim = s
	board = b
	fx = f
	cam = c
	hud = h


func _source_path(id: String, kind: String) -> String:
	if data.special_by_id.has(id):
		return "sfx/specials/%s/%s" % [id, kind]
	return "sfx/gems/%s/%s" % [id, kind]


## Точка над врагом из события (с учётом высоты полёта).
func _enemy_point(e: Dictionary, lift: float) -> Vector3:
	return board.w(e["pos"], (EnemyRenderer.FLY_HEIGHT if bool(e.get("flying", false)) else 0.0) + lift)


## Монеты летят из точки на поле к счётчику золота (§8.4); счётчик «тикает» сам.
func _fly_coins(world: Vector3, count: int) -> void:
	if quiet_ui or Settings.reduce_motion() or cam.cam.is_position_behind(world):
		return
	hud.coins.spawn(cam.cam.unproject_position(world), hud.top.gold_anchor(), count)


## Короткое замедление времени (0.2 с) при раскрытии гема IV–V.
func _slowmo() -> void:
	if allow_slowmo and not Settings.reduce_motion():
		Game.slow_motion(0.3, 0.2)


## Цитадель (выход) — место утечек и краж золота.
func _exit_point() -> Vector3:
	var pts: Array[Vector2i] = sim.grid.route_points
	return board.cell_world(pts[pts.size() - 1])


## Положение звука по горизонтали экрана (−1 … 1) для панорамы боевых звуков.
func _pan(world: Vector3) -> float:
	var vp: Viewport = cam.cam.get_viewport()
	var w: float = vp.get_visible_rect().size.x
	if w <= 0.0 or cam.cam.is_position_behind(world):
		return 0.0
	return clampf(cam.cam.unproject_position(world).x / w * 2.0 - 1.0, -1.0, 1.0)


func _special_color(id: String) -> Color:
	return Color.html(String(data.special(id).get("color", "#ffffff")))


func _slate_color(id: String) -> Color:
	return Color.html(String(data.slate(id).get("color", "#ffffff")))


func _name(id: String) -> String:
	if data.slate_by_id.has(id):
		return TranslationServer.translate(String(data.slate(id)["name_key"]))
	if data.special_by_id.has(id):
		return TranslationServer.translate(String(data.special(id)["name_key"]))
	return TranslationServer.translate(String(data.gem(id).get("name_key", "")))


func present(e: Dictionary) -> void:
	if quiet_ui and String(e["type"]) in ["round_started", "wave_started", "special_forged", "enemy_leaked", "mvp_awarded", "tower_sold", "gem_kept", "gems_combined", "special_upgraded", "special_merged", "slate_made", "slates_combined", "slate_moved", "slate_sold", "tower_moved", "tower_polished", "wave_cleared", "gem_revealed", "luck_upgraded", "life_bought"]:
		_present_quiet(e)
		return
	match String(e["type"]):
		"rock_placed":
			Audio.play("sfx/build/rock_place")
			fx.burst(board.cell_world(e["cell"], 0.1), Color(0.6, 0.65, 0.8), 10, 2.5, 0.12, 0.5, 5.0, 0.6)
			fx.flipbook(board.cell_world(e["cell"], 0.25), "smoke", 1.3, 0.9, Color(0.75, 0.72, 0.68, 0.55))
		"gem_revealed":
			var q: int = int(e["quality"])
			var col: Color = T.gem_color(String(e["gem"]))
			Audio.play("sfx/build/reveal/q%d" % q)
			fx.beam(board.cell_world(e["cell"]), col, 2.5 + 1.2 * float(q), 0.7 + 0.15 * float(q))
			fx.burst(board.cell_world(e["cell"], 0.5), col, 14 + 6 * q, 3.5 + 0.5 * float(q), 0.16, 0.7, 4.0, 1.0, "star")
			if q >= 4:
				_slowmo()
				hud.wave_panel.log_event(String(TranslationServer.translate("LOG_RARE_GEM")) % [_name(String(e["gem"])), String(data.quality(q)["roman"])], "sparkle", T.quality_color(q), "build", board.cell_world(e["cell"]))
		"path_changed":
			Audio.play("sfx/build/path_change")
		"choice_ready":
			Audio.play("sfx/ui/panel_open")
		"gem_kept":
			Audio.play("sfx/choose/keep")
			var kc: Color = T.gem_color(String(e["gem"]))
			fx.ring(board.cell_world(e["cell"], 0.08), kc, 2.6)
			fx.burst(board.cell_world(e["cell"], 0.6), kc, 30, 4.5, 0.18, 0.8, 3.0, 1.0, "star")
			if bool(e.get("downgraded", false)):
				hud.wave_panel.log_event(String(TranslationServer.translate("LOG_DOWNGRADED")) % [_name(String(e["gem"])), String(data.quality(int(e["from_quality"]))["roman"]), String(data.quality(int(e["quality"]))["roman"])], "arrow_down", kc, "build", board.cell_world(e["cell"]))
			else:
				hud.wave_panel.log_event(String(TranslationServer.translate("LOG_KEPT")) % [_name(String(e["gem"])), String(data.quality(int(e["quality"]))["roman"])], "gem", kc, "build", board.cell_world(e["cell"]))
		"gems_combined":
			var cc: Color = T.gem_color(String(e["gem"]))
			Audio.play("sfx/choose/combine_x%d" % int(e["count"]))
			fx.ring(board.cell_world(e["cell"], 0.08), cc, 3.0, 0.6)
			fx.shockwave(board.cell_world(e["cell"], 0.06), cc, 3.2, 0.55, 0.03)
			fx.vortex(board.cell_world(e["cell"], 0.2), cc, 1.6)
			fx.burst(board.cell_world(e["cell"], 0.7), cc, 40, 5.0, 0.18, 0.9, 3.0, 1.0, "star")
			hud.wave_panel.log_event(String(TranslationServer.translate("LOG_COMBINED")) % [_name(String(e["gem"])), String(data.quality(int(e["quality"]))["roman"])], "arrow_up", cc, "build", board.cell_world(e["cell"]))
		"special_forged":
			var sc: Color = _special_color(String(e["special"]))
			var at: Vector3 = board.cell_world(e["cell"])
			Audio.play("sfx/choose/forge_onehit" if bool(e["one_hit"]) else "sfx/choose/forge_collect")
			# Руны рецепта соединяются лучами, вихрь, вспышка, ударная волна и короткий наезд камеры.
			for part: Variant in e.get("parts", []):
				var pc: Vector2i = (part as Dictionary)["cell"]
				if pc != e["cell"]:
					fx.link(board.cell_world(pc, 0.7), at + Vector3(0, 0.9, 0), sc, 0.8)
					fx.ring(board.cell_world(pc, 0.08), sc, 1.2, 0.6)
			fx.vortex(at + Vector3(0, 0.2, 0), sc, 2.2)
			fx.beam(at, sc, 9.0, 1.4)
			fx.ring(at + Vector3(0, 0.08, 0), sc, 4.5, 0.9)
			fx.shockwave(at + Vector3(0, 0.06, 0), sc, 5.0, 0.8, 0.045)
			fx.burst(at + Vector3(0, 0.8, 0), sc, 90, 6.5, 0.2, 1.2, 2.5, 1.0, "star")
			fx.flipbook(at + Vector3(0, 0.6, 0), "explosion", 3.2, 1.1, sc.lightened(0.3), 1.4)
			cam.add_shake(0.3)
			cam.focus_punch(at, 0.9)
			hud.banner.show_banner(_name(String(e["special"])), TranslationServer.translate("BANNER_FORGED_ONEHIT") if bool(e["one_hit"]) else TranslationServer.translate("BANNER_FORGED"), sc, 1.1)
			hud.wave_panel.log_event(String(TranslationServer.translate("LOG_FORGED")) % _name(String(e["special"])), "sparkle", sc, "build", board.cell_world(e["cell"]))
		"special_upgraded":
			var uc: Color = _special_color(String(e["special"]))
			Audio.play("sfx/specials/%s/upgrade" % String(e["special"]))
			fx.ring(board.cell_world(e["cell"], 0.08), uc, 3.2, 0.7)
			fx.burst(board.cell_world(e["cell"], 0.9), uc, 50, 5.0, 0.18, 1.0, 2.5, 1.0, "star")
			hud.wave_panel.log_event(String(TranslationServer.translate("LOG_UPGRADED")) % [_name(String(e["special"])), int(e["level"])], "arrow_up", uc, "build", board.cell_world(e["cell"]))
		"special_merged":
			# Вторая башня перетекает в первую: луч между ними, вихрь, кольцо и баннер с множителем.
			var mc: Color = _special_color(String(e["special"]))
			var mat: Vector3 = board.cell_world(e["cell"])
			var mult: String = String.num(BuildCommands.merge_inherit(data))
			Audio.play("sfx/specials/%s/upgrade" % String(e["special"]))
			fx.link(board.cell_world(e["from"], 0.7), mat + Vector3(0, 0.9, 0), mc, 0.8)
			fx.vortex(mat + Vector3(0, 0.2, 0), mc, 2.0)
			fx.ring(mat + Vector3(0, 0.08, 0), T.GOLD, 4.0, 0.8)
			fx.shockwave(mat + Vector3(0, 0.06, 0), mc, 4.2, 0.7, 0.04)
			fx.burst(mat + Vector3(0, 0.8, 0), mc, 70, 6.0, 0.2, 1.1, 2.5, 1.0, "star")
			cam.add_shake(0.2)
			hud.banner.show_banner(_name(String(e["special"])), String(TranslationServer.translate("BANNER_MERGED")) % mult, mc, 1.0)
			hud.wave_panel.log_event(String(TranslationServer.translate("LOG_MERGED")) % [_name(String(e["special"])), mult], "arrow_up", mc, "build", mat)
		"slate_made", "slates_combined":
			var lc: Color = _slate_color(String(e["slate"]))
			var lat: Vector3 = board.cell_world(e["cell"])
			Audio.play(String(data.slate(String(e["slate"]))["sfx"]))
			if String(e["type"]) == "slate_made":
				for part: Variant in e.get("parts", []):
					var pc2: Vector2i = (part as Dictionary)["cell"]
					if pc2 != e["cell"]:
						fx.link(board.cell_world(pc2, 0.7), lat + Vector3(0, 0.4, 0), lc, 0.7)
			else:
				fx.link(board.cell_world(e["from"], 0.3), lat + Vector3(0, 0.3, 0), lc, 0.7)
			fx.ring(lat + Vector3(0, 0.06, 0), lc, float(data.slate(String(e["slate"]))["radius"]) + 0.6, 0.8)
			fx.shockwave(lat + Vector3(0, 0.05, 0), lc, 3.0, 0.6, 0.03)
			fx.burst(lat + Vector3(0, 0.3, 0), lc, 50, 4.5, 0.18, 0.9, 3.0, 1.0, "star")
			var combo: bool = String(e["type"]) == "slates_combined"
			hud.banner.show_banner(_name(String(e["slate"])), TranslationServer.translate("BANNER_SLATE_COMBO" if combo else "BANNER_SLATE"), lc, 1.0)
			hud.wave_panel.log_event(String(TranslationServer.translate("LOG_SLATE_COMBINED" if combo else "LOG_SLATE_MADE")) % _name(String(e["slate"])), "gem", lc, "build", lat)
		"slate_moved":
			var mc2: Color = _slate_color(String(e["slate"]))
			Audio.play("sfx/build/rock_place")
			fx.link(board.cell_world(e["from"], 0.2), board.cell_world(e["to"], 0.2), mc2, 0.5)
			fx.burst(board.cell_world(e["to"], 0.2), mc2, 24, 3.0, 0.14, 0.6, 3.0, 1.0, "star")
		"tower_moved":
			var tm: TowerState = sim.tower_by_id.get(int(e["tower_id"])) as TowerState
			var tcol: Color = board.tower_color(tm) if tm != null else T.ACCENT
			Audio.play("sfx/build/rock_place")
			fx.link(board.cell_world(e["from"], 0.4), board.cell_world(e["to"], 0.4), tcol, 0.5)
			fx.burst(board.cell_world(e["to"], 0.5), tcol, 24, 3.0, 0.14, 0.6, 3.0, 1.0, "star")
			if tm != null:
				hud.wave_panel.log_event(String(TranslationServer.translate("LOG_TOWER_MOVED")) % [_name(tm.source_id()), int(e["gold"])], "path", tcol, "build", board.cell_world(e["to"]))
		"tower_polished":
			var tpo: TowerState = sim.tower_by_id.get(int(e["tower_id"])) as TowerState
			Audio.play("sfx/economy/quality_up")
			fx.burst(board.cell_world(e["cell"], 1.0), T.ACCENT, 30, 3.0, 0.14, 0.8, 1.5, 1.0, "star")
			if tpo != null:
				hud.wave_panel.log_event(String(TranslationServer.translate("LOG_POLISHED")) % [_name(tpo.source_id()), int(e["level"]), int(e["gold"])], "sparkle", T.ACCENT, "economy", board.cell_world(e["cell"]))
		"slate_sold":
			Audio.play("sfx/economy/sell")
			fx.burst(board.cell_world(e["cell"], 0.3), T.GOLD, 24, 3.5, 0.14, 0.7, 6.0, 1.0, "star")
			hud.wave_panel.log_event(String(TranslationServer.translate("LOG_SOLD")) % [_name(String(e["slate"])), int(e["gold"])], "coin", T.GOLD, "economy", board.cell_world(e["cell"]))
		"slate_pulse":
			var pc3: Color = _slate_color(String(e["slate"]))
			fx.ring(board.w(e["pos"], 0.05), pc3, float(e["radius"]), 0.45)
			Audio.play(String(data.slate(String(e["slate"]))["sfx"]))
		"slate_spell":
			var sc4: Color = T.GOLD if String(e["kind"]) == "gold" else _slate_color(String(e["slate"]))
			fx.burst(board.w(e["pos"], 0.6), sc4, 30, 4.0, 0.16, 0.7, 2.0, 1.0, "flare")
			if String(e["kind"]) == "gold":
				Audio.play("sfx/economy/gold_gain")
		"slate_blast":
			var bc: Color = _slate_color(String(e["slate"]))
			fx.shockwave(board.w(e["pos"], 0.05), bc, float(e["radius"]) + 0.5, 0.5, 0.03)
			fx.burst(board.w(e["pos"], 0.5), bc, 30, 4.0, 0.16, 0.7, 2.0, 1.0, "star")
		"tower_sold":
			Audio.play("sfx/economy/sell")
			fx.burst(board.cell_world(e["cell"], 0.6), T.GOLD, 24, 3.5, 0.14, 0.7, 6.0, 1.0, "star")
			var src: String = String(e["special"]) if not String(e["special"]).is_empty() else String(e["gem"])
			hud.wave_panel.log_event(String(TranslationServer.translate("LOG_SOLD")) % [_name(src), int(e["gold"])], "coin", T.GOLD, "economy", board.cell_world(e["cell"]))
		"wall_formed":
			Audio.play("sfx/build/wall_form")
			fx.burst(board.cell_world(e["cell"], 0.2), Color(0.45, 0.5, 0.65), 8, 2.0, 0.14, 0.6, 5.0, 0.5)
			fx.flipbook(board.cell_world(e["cell"], 0.0), "dust", 1.4, 1.2, Color(0.7, 0.68, 0.66, 0.45))
		"wall_broken":
			Audio.play("sfx/build/wall_break")
			fx.burst(board.cell_world(e["cell"], 0.3), Color(0.5, 0.55, 0.75), 30, 4.0, 0.16, 0.8, 8.0, 0.8)
			fx.flipbook(board.cell_world(e["cell"], 0.3), "smoke", 1.8, 1.1, Color(0.62, 0.6, 0.6, 0.7))
		"life_bought":
			Audio.play("sfx/economy/buy_life")
		"mvp_awarded":
			Audio.play("sfx/economy/mvp")
			fx.burst(board.cell_world(e["cell"], 1.4), T.GOLD, 26, 3.0, 0.14, 0.8, 1.5, 1.0, "star")
			var t: TowerState = sim.tower_by_id.get(int(e["tower_id"])) as TowerState
			if t != null:
				hud.wave_panel.log_event(String(TranslationServer.translate("LOG_MVP")) % [_name(t.source_id()), int(e["stacks"]), T.format_number(float(e["damage"]))], "crown", T.GOLD, "economy", board.cell_world(e["cell"]))
		"luck_upgraded":
			Audio.play("sfx/economy/quality_up")
			hud.top.flash_luck()
		"wave_started":
			var air: bool = bool(e["air"])
			var boss: bool = bool(e["boss"])
			Audio.play("sfx/waves/start")
			if air:
				Audio.play("sfx/waves/air_warning")
			if boss:
				Audio.play("sfx/boss/warning")
				aberration = 0.012
			var color: Color = T.BOSS if boss else (T.AIR if air else T.ACCENT)
			var tr_: Callable = TranslationServer.translate
			var sub: String = String(tr_.call("WAVE_KIND_BOSS")) if boss else (String(tr_.call("WAVE_KIND_AIR")) if air else String(tr_.call("MOD_" + String(e["modifier"]).to_upper())))
			hud.banner.show_banner(String(tr_.call("BANNER_WAVE")) % int(e["wave"]), sub, color)
			board.show_air_path(air)
			if air:
				hud.wave_panel.log_event(String(tr_.call("LOG_AIR_WAVE")) % int(e["wave"]), "air", T.AIR)
			if boss:
				hud.wave_panel.log_event(String(tr_.call("LOG_BOSS_WAVE")) % int(e["wave"]), "boss", T.BOSS)
		"enemy_spawned":
			if not bool(e["boss"]) and String(e["archetype"]) != "colossus":
				Audio.play("sfx/enemies/%s/spawn" % String(e["archetype"]))
		"boss_spawned":
			Audio.play("sfx/boss/spawn")
			darken = 1.0
			var arch_b: Dictionary = data.archetype(String(e.get("archetype", "")))
			if not arch_b.is_empty() and String(e.get("archetype", "")) != "colossus":
				hud.banner.show_banner(TranslationServer.translate(String(arch_b["name_key"])),
					TranslationServer.translate("BOSS_INTRO_FINALE" if bool(e.get("finale", false)) else "BOSS_INTRO_SUB"), T.BOSS, 1.8)
			cam.add_shake(0.35)
		"tower_fired":
			Audio.play(_source_path(String(e["gem"]), "attack"), 0.0, 1.0, _pan(board.w(e["from"])))
			board.tower_attack(int(e["tower_id"]))
		"hit":
			var gem: String = String(e["gem"])
			var hp: Vector3 = board.w(e["pos"], (EnemyRenderer.FLY_HEIGHT if bool(e["flying"]) else 0.0) + 0.5)
			var hpan: float = _pan(hp)
			if not gem.is_empty():
				Audio.play(_source_path(gem, "impact"), 0.0, 1.0, hpan)
				if gem == "emerald":
					Audio.play("sfx/status/poison_tick", 0.0, 1.0, hpan)
				elif gem == "aquamarine":
					Audio.play("sfx/status/slow_apply", 0.0, 1.0, hpan)
			var victim: EnemyState = sim.enemy_by_id.get(int(e["enemy_id"])) as EnemyState
			if victim != null and not victim.boss:
				Audio.play("sfx/enemies/%s/hurt" % victim.archetype, 0.0, 1.0, hpan)
			var dc: Color = T.dtype_color(String(e["dtype"]))
			fx.burst(hp, dc, 3, 2.5, 0.09, 0.3, 4.0, 1.0, "flare")
			if bool(e["crit"]):
				Audio.play("sfx/status/crit")
				fx.burst(hp, Color("fff1a8"), 10, 4.0, 0.12, 0.4, 2.0, 1.0, "star")
			fx.number(hp + Vector3(0, 0.3, 0), float(e["damage"]), dc, bool(e["crit"]), int(e["enemy_id"]))
		"splash":
			fx.ring(board.w(e["pos"], 0.08), T.gem_color(String(e["gem"])), float(e["radius"]), 0.35)
		"aura_pulse":
			var pc: Color = _special_color(String(e["special"]))
			fx.ring(board.w(e["pos"], 0.06), pc, float(e["radius"]), 0.5 if String(e["kind"]) == "burn" else 0.9)
			if String(e["kind"]) == "burn":
				fx.burst(board.w(e["pos"], 0.4), pc, 6, 2.0, 0.12, 0.6, -1.0, 1.0, "flare")
				fx.flipbook(board.w(e["pos"], 0.0), "flame", 1.6, 0.8, pc.lightened(0.2), 1.2)
			Audio.play("sfx/specials/%s/attack" % String(e["special"]))
		"aura_flash":
			var fc: Color = _special_color(String(e["special"]))
			fx.shockwave(board.w(e["pos"], 0.06), fc, float(e["radius"]) * 1.15, 0.6, 0.04)
			fx.burst(board.w(e["pos"], 0.6), fc, 60, 6.0, 0.2, 0.8, 1.0, 1.0, "flare")
			Audio.play("sfx/specials/%s/ability" % String(e["special"]))
			cam.add_shake(0.15)
		"frozen":
			var zp: Vector3 = board.w(e["pos"], (EnemyRenderer.FLY_HEIGHT if bool(e["flying"]) else 0.0) + 0.4)
			fx.burst(zp, Color("bff6ff"), 12, 2.5, 0.12, 0.6, 2.0, 1.0, "star")
			Audio.play("sfx/specials/frostwell/ability")
		"pool_created":
			fx.pool(board.w(e["pos"], 0.03), _special_color("blightbloom"), float(e["radius"]), float(e["duration"]))
		"blight_explode":
			fx.ring(board.w(e["pos"], 0.08), _special_color("blightbloom"), float(e["radius"]), 0.45)
			fx.burst(board.w(e["pos"], 0.4), _special_color("blightbloom"), 24, 4.0, 0.16, 0.6, 3.0)
			fx.flipbook(board.w(e["pos"], 0.4), "smoke", float(e["radius"]) * 1.4, 1.2, _special_color("blightbloom").darkened(0.15))
			Audio.play("sfx/specials/blightbloom/ability")
		"enemy_died":
			var arch: String = String(e["archetype"])
			var a: Dictionary = data.archetypes.get(arch, {})
			var dp: Vector3 = board.w(e["pos"], (EnemyRenderer.FLY_HEIGHT if bool(e["flying"]) else 0.0) + 0.3)
			var dc: Color = Color.html(String(a.get("color", "#ffffff")))
			if bool(e["boss"]):
				Audio.play("sfx/boss/death")
				cam.add_shake(0.5)
				aberration = 0.016
				fx.shockwave(board.w(e["pos"], 0.06), dc, 6.0, 0.9, 0.06)
				hud.wave_panel.log_event(TranslationServer.translate("LOG_BOSS_DOWN"), "crown", T.GOLD, "combat", board.w(e["pos"]))
			else:
				Audio.play("sfx/enemies/%s/death" % arch, 0.0, 1.0, _pan(dp))
			var bounty: int = int(e["bounty"])
			if bounty >= 10 or bool(e["golden"]):
				_fly_coins(dp, clampi(int(bounty / 10.0), 3, 10))
			elif bounty > 0 and Time.get_ticks_msec() >= _coin_next_ms:
				_coin_next_ms = Time.get_ticks_msec() + 120
				_fly_coins(dp, 1)
			# Искры, тяжёлые осколки, падающие на поле, и клуб дыма (у босса — взрыв).
			fx.burst(dp, dc, 12 if not bool(e["boss"]) else 60, 3.5, 0.14, 0.6, 7.0, 1.0, "flare")
			fx.burst(dp, dc.darkened(0.3), 5 if not bool(e["boss"]) else 30, 2.5, 0.22, 0.8, 14.0, 0.6)
			if bool(e["boss"]):
				fx.flipbook(dp + Vector3(0, 0.6, 0), "explosion", 5.0, 1.6, Color(1, 1, 1), 1.3)
			else:
				fx.flipbook(dp, "smoke", 0.9 + float(a.get("size", 0.3)) * 2.0, 0.8, Color(dc.lerp(Color(0.55, 0.52, 0.5), 0.6), 0.6))
		"enemy_leaked":
			Audio.play("sfx/game/life_lost")
			flash = 1.0
			hud.wave_panel.log_event(String(TranslationServer.translate("LOG_LEAK")) % int(e["damage"]), "heart", T.LIFE, "combat", _exit_point())
		"wave_cleared":
			var perfect: bool = bool(e["perfect"])
			Audio.play("sfx/waves/perfect" if perfect else "sfx/waves/clear")
			Audio.play("sfx/economy/gold_gain")
			board.show_air_path(false)
			var text: String = String(TranslationServer.translate("LOG_WAVE_CLEAR")) % [int(e["wave"]), int(e["gold"])]
			if perfect:
				text += " · " + String(TranslationServer.translate("LOG_PERFECT"))
			hud.wave_panel.log_event(text, "check", T.SUCCESS)
			_fly_coins(_exit_point() + Vector3(0, 1.0, 0), 8)
		"round_started":
			hud.banner.show_banner(String(TranslationServer.translate("BANNER_ROUND")) % int(e["round"]), TranslationServer.translate("BANNER_ROUND_SUB"), T.ACCENT, 0.9)
		"hit_blocked":
			var kind: String = String(e["kind"])
			var bp: Vector3 = _enemy_point(e, 0.8)
			fx.text(bp, String(TranslationServer.translate("FX_BLOCK_" + kind.to_upper())), BLOCK_COLORS.get(kind, T.TEXT_DIM))
			fx.burst(bp, BLOCK_COLORS.get(kind, T.TEXT_DIM), 4, 1.8, 0.08, 0.3, 2.0)
			Audio.play("sfx/traits/" + kind)
		"trait_proc":
			var tr_id: String = String(e["trait"])
			var tp: Vector3 = _enemy_point(e, 0.4)
			match tr_id:
				"blink":
					fx.burst(tp, Color("c9a2ff"), 22, 3.5, 0.12, 0.45, 0.0)
					fx.ring(board.w(e["pos"], 0.06), Color("c9a2ff"), 0.8, 0.3)
				"rush":
					fx.burst(tp, Color("ff6a4d"), 16, 4.0, 0.1, 0.4, 1.0)
				"carapace":
					fx.burst(tp, Color("d8b27a"), 14, 2.5, 0.12, 0.5, 4.0)
				"hardening":
					fx.burst(tp, Color("a9b4c8"), 6, 1.6, 0.09, 0.35, 4.0)
			Audio.play("sfx/traits/" + tr_id)
		"disarm":
			var dc: Color = Color("ff5470")
			fx.ring(board.w(e["pos"], 0.06), dc, float(e["radius"]), 0.5)
			for tid: Variant in e["towers"]:
				var dt: TowerState = sim.tower_by_id.get(int(tid)) as TowerState
				if dt != null:
					fx.burst(board.w(dt.pos, 0.9), dc, 10, 2.5, 0.1, 0.5, 3.0)
			board.mark_disarmed(e["towers"], float(e["duration"]))
			Audio.play("sfx/traits/disarm")
		"gold_stolen":
			Audio.play("sfx/economy/gold_stolen")
			hud.wave_panel.log_event(String(TranslationServer.translate("LOG_GOLD_STOLEN")) % int(e["amount"]), "coin", T.DANGER, "economy", _exit_point())
		"shield_broken":
			fx.burst(_enemy_point(e, 0.5), Color("9fe8ff"), 26, 4.5, 0.13, 0.5, 5.0)
			Audio.play("sfx/status/armor_break")
		"stripped":
			fx.burst(_enemy_point(e, 0.5), Color("e8a04d") if String(e["what"]) == "carapace" else Color("9fe8ff"), 20, 3.5, 0.12, 0.5, 5.0)
			fx.text(_enemy_point(e, 0.9), String(TranslationServer.translate("FX_STRIPPED")), T.GOLD)
			Audio.play("sfx/status/armor_break")
		"stunned":
			fx.burst(_enemy_point(e, 0.7), Color("fff1a8"), 8, 1.5, 0.09, 0.5, -0.5)
			Audio.play("sfx/status/stun")
		"pull":
			fx.ring(board.w(e["pos"], 0.06), _special_color("gravity_geode"), float(e["radius"]), 0.4)
			Audio.play("sfx/specials/gravity_geode/ability")
		"discharge":
			fx.ring(board.w(e["pos"], 0.3), _special_color("stormspire"), float(e["radius"]), 0.3)
			fx.burst(board.w(e["pos"], 0.4), Color("bfe3ff"), 10, 4.0, 0.08, 0.25, 0.0, 1.0, "bolt")
			Audio.play("sfx/specials/stormspire/ability")
		"shockwave":
			fx.shockwave(board.w(e["pos"], 0.06), _special_color("quake_heart"), float(e["radius"]), 0.6, 0.04)
			fx.burst(board.w(e["pos"], 0.3), _special_color("quake_heart"), 40, 6.0, 0.18, 0.6, 9.0)
			fx.flipbook(board.w(e["pos"], 0.0), "dust", float(e["radius"]) * 1.1, 1.3, Color(0.72, 0.66, 0.58, 0.75))
			cam.add_shake(0.2)
			Audio.play("sfx/specials/quake_heart/ability")
		"golden":
			fx.burst(_enemy_point(e, 0.5), T.GOLD, 24, 3.0, 0.12, 0.7, 1.0, 1.0, "star")
			Audio.play("sfx/economy/golden")
		"enemy_split":
			fx.burst(board.w(e["pos"], 0.4), Color("ffb3e6"), 20, 3.5, 0.12, 0.5, 6.0, 1.0, "star")
		"boss_phase":
			var key: String = String(e["key"])
			cam.add_shake(0.4)
			aberration = 0.014
			fx.shockwave(board.w(e["pos"], 0.06), T.BOSS, 4.5, 0.8, 0.05)
			fx.burst(_enemy_point(e, 0.8), T.BOSS, 50, 5.0, 0.18, 0.8, 3.0, 1.0, "flare")
			fx.flipbook(_enemy_point(e, 0.8), "explosion", 3.6, 1.2, T.BOSS.lightened(0.4), 1.2)
			Audio.play("sfx/boss/phase_change")
			if not key.is_empty():
				hud.banner.show_banner(String(TranslationServer.translate("BOSS_PHASE")) % int(e["phase"]), TranslationServer.translate(key), T.BOSS, 1.0)
				hud.wave_panel.log_event(String(TranslationServer.translate("LOG_BOSS_PHASE")) % TranslationServer.translate(key), "boss", T.BOSS, "combat", board.w(e["pos"]))
		"boss_summon":
			fx.ring(board.w(e["pos"], 0.08), Color("c86bff"), 1.6, 0.5)
			fx.burst(_enemy_point(e, 0.6), Color("c86bff"), 24, 3.5, 0.14, 0.6, 2.0)
			Audio.play("sfx/boss/summon")


func decay(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 2.2)
	darken = maxf(0.0, darken - delta * 0.6)
	aberration = maxf(0.0, aberration - delta * 0.02)


## Чужое поле: только эффекты на арене, без журнала/баннеров/HUD.
func _present_quiet(e: Dictionary) -> void:
	match String(e["type"]):
		"gem_revealed":
			fx.beam(board.cell_world(e["cell"]), T.gem_color(String(e["gem"])), 2.5 + 1.2 * float(e["quality"]), 0.8)
		"slate_made", "slates_combined":
			fx.beam(board.cell_world(e["cell"]), _slate_color(String(e["slate"])), 4.0, 1.0)
		"special_forged", "special_merged":
			var sc: Color = _special_color(String(e["special"]))
			fx.beam(board.cell_world(e["cell"]), sc, 9.0, 1.4)
			fx.burst(board.cell_world(e["cell"], 0.8), sc, 60, 6.0, 0.2, 1.0, 2.5)
		"wave_started":
			board.show_air_path(bool(e["air"]))
		"wave_cleared":
			board.show_air_path(false)
