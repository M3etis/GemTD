extends SceneTree
## Процедурный генератор звукового пака по умолчанию (res://audio).
## Запуск: godot --headless --path . -s res://tools/sfx_generator.gd [-- --only=sfx/ui]
## Для каждого события манифеста пишет 1–3 варианта WAV (16 бит, моно, 44.1 кГц).
## Генерация детерминирована: одинаковый результат при каждом запуске.

const SR: int = 44100
const MANIFEST: String = "res://audio/audio_manifest.json"
const GEM_BASE: Dictionary = {
	"ruby": 220.0, "sapphire": 330.0, "emerald": 262.0, "topaz": 147.0,
	"amethyst": 523.0, "aquamarine": 659.0, "opal": 392.0, "diamond": 880.0,
}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _initialize() -> void:
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary:
		push_error("нет манифеста")
		quit(1)
		return
	var ids: Array = (manifest["events"] as Dictionary).keys()
	ids.sort()
	var written: int = 0
	for id: String in ids:
		if not only.is_empty() and not id.begins_with(only):
			continue
		var variants: int = _variant_count(id)
		var dir: String = "res://audio".path_join(id)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".wav") or f.ends_with(".import"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
		# Фоновой атмосферы во встроенном паке нет: низкий дрон звучал как постоянное гудение.
		# Событие остаётся для звуковых паков (ambience/arena из пака играет как раньше).
		if id.begins_with("ambience/"):
			continue
		if id.begins_with("music/"):
			var music: PackedFloat32Array = MusicSynth.new().render(id.get_file())
			if music.is_empty():
				push_error("нет рецепта для " + id)
				continue
			_save(music, ProjectSettings.globalize_path(dir.path_join("%s.wav" % id.get_file())), MusicSynth.SR)
			written += 1
			continue
		for v: int in variants:
			_rng.seed = hash(id) + v * 7919
			var buf: PackedFloat32Array = _render(id, v)
			if buf.is_empty():
				push_error("нет рецепта для " + id)
				continue
			_save(buf, ProjectSettings.globalize_path(dir.path_join("%s_%d.wav" % [id.get_file(), v + 1])))
			written += 1
	print("sfx_generator: записано %d файлов" % written)
	quit(0)


func _variant_count(id: String) -> int:
	if id.begins_with("sfx/gems/") or id.begins_with("sfx/enemies/") or id.ends_with("/attack") or id in ["sfx/ui/hover", "sfx/ui/click", "sfx/build/rock_place", "sfx/build/wall_form"]:
		return 3
	return 1


# --- Рецепты ---------------------------------------------------------------

func _render(id: String, v: int) -> PackedFloat32Array:
	var j: float = 1.0 + (_rng.randf() - 0.5) * 0.08
	var parts: PackedStringArray = id.split("/")
	if id.begins_with("sfx/gems/"):
		return _gem(parts[2], parts[3], j)
	if id.begins_with("sfx/specials/"):
		return _special(parts[2], parts[3], j)
	if id.begins_with("sfx/enemies/"):
		match parts[3]:
			"spawn":
				return _enemy_spawn(parts[2], j)
			"hurt":
				return _enemy_hurt(parts[2], j)
		return _enemy_death(parts[2], j)
	if id.begins_with("sfx/traits/"):
		return _trait(parts[2], j)
	if id.begins_with("sfx/build/reveal/q"):
		return _reveal(int(id.right(1)))
	match id:
		"sfx/ui/hover":
			return _tone_sweep(0.045, 1900.0 * j, 2300.0 * j, "sine", 0.35, 0.003)
		"sfx/ui/click":
			var b: PackedFloat32Array = _tone_sweep(0.05, 950.0 * j, 700.0 * j, "square", 0.25, 0.001)
			_mix(b, _noise(0.02, 0.4, 6000.0, 1200.0), 0)
			return b
		"sfx/ui/confirm":
			return _arp([660.0, 990.0, 1320.0], 0.055, 0.22, "triangle", 0.45)
		"sfx/ui/cancel":
			return _arp([880.0, 587.0], 0.06, 0.18, "triangle", 0.4)
		"sfx/ui/error":
			return _buzz(0.18, 170.0, 0.4)
		"sfx/ui/panel_open":
			return _whoosh(0.22, 400.0, 3000.0, 0.45)
		"sfx/ui/panel_close":
			return _whoosh(0.2, 2600.0, 350.0, 0.4)
		"sfx/ui/toast":
			return _chime([1318.0, 2637.0], 0.45, 0.4)
		"sfx/ui/tab_switch":
			return _tone_sweep(0.035, 1400.0, 1250.0, "triangle", 0.35, 0.001)
		"sfx/build/rock_place":
			var b: PackedFloat32Array = _tone_sweep(0.16, 110.0 * j, 48.0 * j, "sine", 0.9, 0.002)
			_mix(b, _noise(0.09, 0.5, 900.0 * j, 80.0), 0)
			return b
		"sfx/build/invalid":
			return _buzz(0.14, 120.0, 0.35)
		"sfx/build/wall_form":
			var b: PackedFloat32Array = _noise(0.38, 0.55, 700.0 * j, 60.0)
			_mix(b, _tone_sweep(0.3, 70.0 * j, 45.0, "sine", 0.6, 0.01), 0)
			return b
		"sfx/build/path_change":
			return _whoosh(0.16, 900.0, 1600.0, 0.3)
		"sfx/choose/keep":
			var b: PackedFloat32Array = _whoosh(0.4, 300.0, 4000.0, 0.35)
			_mix(b, _chime([784.0, 1175.0, 1568.0], 0.9, 0.45), int(0.12 * SR))
			return b
		"sfx/status/crit":
			var b: PackedFloat32Array = _chime([1046.0, 1568.0, 2093.0], 0.3, 0.5)
			_mix(b, _noise(0.05, 0.5, 9000.0, 2000.0), 0)
			return b
		"sfx/boss/warning":
			return _horn(1.6, [55.0, 82.4, 110.0], 0.7)
		"sfx/boss/spawn":
			var b: PackedFloat32Array = _noise(1.2, 0.6, 300.0, 30.0)
			_mix(b, _tone_sweep(1.1, 60.0, 35.0, "saw", 0.4, 0.05), 0)
			return b
		"sfx/boss/death":
			var b: PackedFloat32Array = _explosion(1.4, 0.9)
			_mix(b, _arp([392.0, 523.0, 659.0, 784.0], 0.09, 0.9, "triangle", 0.35), int(0.25 * SR))
			return b
		"sfx/waves/start":
			return _horn(0.9, [110.0, 165.0, 220.0], 0.55)
		"sfx/waves/clear":
			return _arp([523.0, 659.0, 784.0, 1046.0], 0.08, 0.7, "triangle", 0.4)
		"sfx/waves/perfect":
			var b: PackedFloat32Array = _arp([659.0, 784.0, 988.0, 1318.0], 0.07, 0.8, "triangle", 0.4)
			_mix(b, _sparkle(0.9, 0.25), int(0.2 * SR))
			return b
		"sfx/waves/air_warning":
			var b: PackedFloat32Array = _whoosh(1.0, 300.0, 2500.0, 0.4)
			_mix(b, _tone_sweep(0.8, 880.0, 1320.0, "sine", 0.25, 0.1), int(0.1 * SR))
			return b
		"sfx/waves/countdown":
			return _tone_sweep(0.09, 1046.0, 1046.0, "sine", 0.45, 0.002)
		"sfx/economy/gold_gain":
			return _arp([1568.0, 2093.0], 0.05, 0.25, "sine", 0.35)
		"sfx/economy/quality_up":
			var b: PackedFloat32Array = _arp([523.0, 784.0, 1046.0, 1568.0, 2093.0], 0.05, 0.6, "triangle", 0.35)
			_mix(b, _sparkle(0.7, 0.25), int(0.15 * SR))
			return b
		"sfx/game/life_lost":
			var b: PackedFloat32Array = _tone_sweep(0.35, 160.0, 60.0, "sine", 0.8, 0.002)
			_mix(b, _noise(0.25, 0.5, 2500.0, 300.0), 0)
			return b
		"sfx/game/victory":
			var b: PackedFloat32Array = _arp([392.0, 523.0, 659.0, 784.0, 1046.0], 0.12, 1.8, "triangle", 0.35)
			_mix(b, _chime([523.0, 659.0, 784.0, 1046.0], 2.0, 0.35), int(0.6 * SR))
			return b
		"sfx/game/defeat":
			return _arp([440.0, 392.0, 349.0, 262.0], 0.22, 1.6, "saw", 0.22)
		"sfx/game/new_record":
			var b: PackedFloat32Array = _arp([523.0, 659.0, 784.0, 1046.0, 1318.0, 1568.0], 0.06, 0.9, "square", 0.18)
			_mix(b, _sparkle(1.0, 0.3), int(0.3 * SR))
			return b
		"sfx/choose/combine_x2":
			var b: PackedFloat32Array = _whoosh(0.35, 500.0, 3500.0, 0.3)
			_mix(b, _chime([659.0, 988.0], 0.6, 0.45), int(0.2 * SR))
			return b
		"sfx/choose/combine_x4":
			var b: PackedFloat32Array = _whoosh(0.45, 400.0, 4500.0, 0.35)
			_mix(b, _arp([523.0, 784.0, 1046.0, 1318.0], 0.05, 0.7, "triangle", 0.4), int(0.2 * SR))
			_mix(b, _sparkle(0.8, 0.2), int(0.3 * SR))
			return b
		"sfx/choose/forge_onehit", "sfx/choose/forge_collect":
			var root: float = 392.0 if id.ends_with("onehit") else 349.0
			var b: PackedFloat32Array = _whoosh(0.7, 150.0, 5000.0, 0.4)
			_mix(b, _horn(1.0, [root * 0.5, root * 0.75], 0.35), int(0.25 * SR))
			_mix(b, _chime([root * 2.0, root * 2.5, root * 3.0, root * 4.0], 1.6, 0.45), int(0.55 * SR))
			_mix(b, _sparkle(1.4, 0.3), int(0.5 * SR))
			return b
		"sfx/build/wall_break":
			var b: PackedFloat32Array = _noise(0.45, 0.6, 2400.0 * j, 120.0)
			_mix(b, _tone_sweep(0.3, 130.0, 50.0, "triangle", 0.5, 0.003), 0)
			for k: int in 4:
				_mix(b, _noise(0.06, 0.35, 4000.0, 800.0), int((0.08 + 0.07 * float(k)) * SR))
			return b
		"sfx/economy/sell":
			return _arp([2093.0, 1568.0, 1318.0], 0.05, 0.3, "sine", 0.35)
		"sfx/economy/buy_life":
			var b: PackedFloat32Array = _tone_sweep(0.12, 90.0, 60.0, "sine", 0.7, 0.003)
			_mix(b, _tone_sweep(0.12, 90.0, 60.0, "sine", 0.6, 0.003), int(0.2 * SR))
			_mix(b, _chime([1046.0, 1568.0], 0.6, 0.35), int(0.35 * SR))
			return b
		"sfx/economy/mvp":
			return _arp([784.0, 988.0, 1175.0, 1568.0], 0.07, 0.6, "square", 0.16)
		"sfx/boss/phase_change":
			var bp: PackedFloat32Array = _horn(1.1, [98.0, 147.0, 196.0], 0.45)
			_mix(bp, _whoosh(0.9, 200.0, 2400.0, 0.25), 0)
			return bp
		"sfx/boss/summon":
			var bs: PackedFloat32Array = _tone_sweep(0.6, 140.0, 420.0, "saw", 0.3, 0.05)
			_mix(bs, _noise(0.5, 0.25, 800.0, 3000.0), 0)
			return bs
		"sfx/status/stun":
			return _chime([1320.0, 1760.0, 1980.0], 0.3, 0.3)
		"sfx/status/armor_break":
			var ab: PackedFloat32Array = _noise(0.22, 0.5, 6000.0, 1200.0)
			_mix(ab, _chime([620.0, 930.0], 0.2, 0.3), 0)
			return ab
		"sfx/economy/gold_stolen":
			return _arp([988.0, 784.0, 659.0, 523.0], 0.06, 0.45, "square", 0.16)
		"sfx/economy/golden":
			var gd: PackedFloat32Array = _arp([1047.0, 1319.0, 1568.0, 2093.0], 0.05, 0.6, "triangle", 0.25)
			_mix(gd, _sparkle(0.6, 0.25), 0)
			return gd
		"sfx/game/damage_test_start":
			var ds: PackedFloat32Array = _horn(0.9, [131.0, 196.0, 262.0], 0.4)
			_mix(ds, _tone_sweep(0.8, 80.0, 160.0, "sine", 0.4, 0.05), 0)
			return ds
		"sfx/net/match_start":
			var ms: PackedFloat32Array = _horn(1.0, [147.0, 220.0, 294.0], 0.4)
			_mix(ms, _arp([587.0, 740.0, 880.0], 0.09, 0.6, "triangle", 0.2), int(0.3 * SR))
			return ms
		"sfx/net/player_joined":
			return _arp([660.0, 990.0], 0.07, 0.35, "triangle", 0.3)
		"sfx/net/player_left":
			return _arp([990.0, 660.0], 0.07, 0.35, "triangle", 0.3)
		"sfx/net/ready":
			return _chime([1175.0, 1760.0], 0.2, 0.3)
		"sfx/net/opponent_eliminated":
			var oe: PackedFloat32Array = _tone_sweep(0.6, 330.0, 110.0, "triangle", 0.4, 0.01)
			_mix(oe, _noise(0.4, 0.2, 800.0, 200.0), 0)
			return oe
		"sfx/status/poison_tick":
			var pt: PackedFloat32Array = _tone_sweep(0.09, 300.0 * j, 520.0 * j, "sine", 0.35, 0.004)
			_mix(pt, _noise(0.06, 0.15, 1500.0, 600.0), 0)
			return pt
		"sfx/status/slow_apply":
			var sa: PackedFloat32Array = _noise(0.2, 0.3, 9000.0, 4000.0)
			_mix(sa, _chime([2093.0 * j, 2637.0 * j], 0.2, 0.2), 0)
			return sa
		"sfx/game/damage_test_end":
			return _arp([523.0, 659.0, 784.0, 1047.0, 1319.0], 0.08, 0.9, "triangle", 0.3)
	return PackedFloat32Array()


## Звуки трейтов: короткие узнаваемые «сигналы» поверх боя.
func _trait(id: String, j: float) -> PackedFloat32Array:
	match id:
		"rush":
			return _whoosh(0.35, 400.0 * j, 2600.0 * j, 0.4)
		"blink":
			var b: PackedFloat32Array = _tone_sweep(0.18, 1800.0 * j, 300.0 * j, "sine", 0.35, 0.002)
			_mix(b, _sparkle(0.2, 0.2), 0)
			return b
		"evasion":
			return _whoosh(0.12, 1500.0 * j, 5000.0 * j, 0.3)
		"antimagic":
			return _buzz(0.16, 110.0 * j, 0.35)
		"ethereal":
			return _tone_sweep(0.22, 700.0 * j, 1400.0 * j, "sine", 0.25, 0.04)
		"refraction":
			return _chime([1568.0 * j, 2350.0 * j], 0.15, 0.3)
		"hardening":
			return _chime([311.0 * j, 466.0 * j], 0.12, 0.3)
		"carapace":
			var c: PackedFloat32Array = _noise(0.14, 0.4, 900.0, 300.0)
			_mix(c, _chime([220.0 * j, 330.0 * j], 0.14, 0.25), 0)
			return c
		"disarm":
			var d: PackedFloat32Array = _zap(0.3, 240.0 * j, 0.4)
			_mix(d, _buzz(0.3, 60.0, 0.25), 0)
			return d
		"thief":
			return _arp([880.0 * j, 740.0 * j, 587.0 * j], 0.05, 0.3, "square", 0.14)
	return PackedFloat32Array()


func _special(sp: String, kind: String, j: float) -> PackedFloat32Array:
	var base: float = {"beacon_lens": 440.0, "cinder_crown": 220.0, "skypiercer": 660.0, "frostwell": 880.0, "blightbloom": 262.0,
		"rust_obelisk": 175.0, "gravity_geode": 110.0, "stormspire": 523.0, "razor_prism": 988.0, "quake_heart": 82.0,
		"gilded_idol": 784.0, "warbanner_crystal": 294.0, "titanbane": 131.0}.get(sp, 440.0) * j
	match kind:
		"upgrade":
			var b: PackedFloat32Array = _arp([base, base * 1.25, base * 1.5, base * 2.0], 0.06, 0.7, "triangle", 0.4)
			_mix(b, _sparkle(0.8, 0.22), int(0.15 * SR))
			return b
		"attack":
			match sp:
				"cinder_crown":
					return _noise(0.25, 0.35, 1600.0, 500.0)
				"frostwell":
					return _whoosh(0.4, 3000.0, 6000.0, 0.25)
				"skypiercer":
					var b2: PackedFloat32Array = _tone_sweep(0.08, base * 2.2, base, "saw", 0.35, 0.001)
					_mix(b2, _noise(0.05, 0.3, 6000.0, 2000.0), 0)
					return b2
				"blightbloom":
					return _tone_sweep(0.16, base * 1.4, base * 0.6, "sine", 0.55, 0.004)
				"rust_obelisk":
					var r1: PackedFloat32Array = _tone_sweep(0.14, base * 2.0, base, "saw", 0.35, 0.003)
					_mix(r1, _noise(0.08, 0.3, 2500.0, 600.0), 0)
					return r1
				"gravity_geode":
					return _tone_sweep(0.24, base * 3.0, base, "sine", 0.6, 0.01)
				"stormspire":
					var s1: PackedFloat32Array = _zap(0.22, base * 2.0, 0.5)
					_mix(s1, _noise(0.15, 0.3, 9000.0, 3000.0), 0)
					return s1
				"razor_prism":
					return _tone_sweep(0.07, base * 3.0, base * 1.2, "triangle", 0.45, 0.001)
				"quake_heart":
					var q1: PackedFloat32Array = _tone_sweep(0.3, base * 2.0, base * 0.7, "sine", 0.85, 0.003)
					_mix(q1, _noise(0.12, 0.45, 900.0, 150.0), 0)
					return q1
				"gilded_idol":
					return _chime([base, base * 1.26, base * 1.5], 0.2, 0.3)
				"titanbane":
					var t1: PackedFloat32Array = _tone_sweep(0.35, base * 4.0, base, "saw", 0.45, 0.005)
					_mix(t1, _whoosh(0.3, 800.0, 3000.0, 0.25), 0)
					return t1
		"impact":
			match sp:
				"skypiercer":
					return _chime([base * 1.5, base * 2.3], 0.12, 0.4)
				"stormspire":
					return _zap(0.1, base * 3.0, 0.35)
				"cinder_crown":
					var c2: PackedFloat32Array = _noise(0.18, 0.45, 3000.0, 600.0)
					_mix(c2, _tone_sweep(0.12, 300.0, 120.0, "saw", 0.2, 0.002), 0)
					return c2
				"blightbloom":
					var b3: PackedFloat32Array = _noise(0.2, 0.45, 1400.0, 200.0)
					_mix(b3, _tone_sweep(0.15, 180.0, 90.0, "sine", 0.4, 0.003), 0)
					return b3
				"rust_obelisk":
					var r2: PackedFloat32Array = _noise(0.12, 0.4, 2000.0, 400.0)
					_mix(r2, _chime([base * 3.1], 0.1, 0.2), 0)
					return r2
				"gravity_geode":
					return _tone_sweep(0.2, base * 1.5, base * 0.5, "sine", 0.6, 0.003)
				"razor_prism":
					return _chime([base * 1.5, base * 2.2], 0.1, 0.35)
				"quake_heart":
					return _explosion(0.5, 0.85)
				"gilded_idol":
					return _sparkle(0.16, 0.3)
				"titanbane":
					var t2: PackedFloat32Array = _explosion(0.3, 0.6)
					_mix(t2, _chime([base * 4.0, base * 6.0], 0.25, 0.25), 0)
					return t2
		"ability":
			match sp:
				"cinder_crown":
					var b4: PackedFloat32Array = _explosion(0.7, 0.8)
					_mix(b4, _whoosh(0.5, 300.0, 3000.0, 0.3), 0)
					return b4
				"frostwell":
					var b5: PackedFloat32Array = _noise(0.18, 0.5, 9000.0, 4000.0)
					_mix(b5, _chime([base * 2.0, base * 3.1], 0.25, 0.3), 0)
					return b5
				"blightbloom":
					var b6: PackedFloat32Array = _explosion(0.45, 0.6)
					_mix(b6, _noise(0.35, 0.4, 900.0, 200.0), int(0.05 * SR))
					return b6
				"rust_obelisk":
					var r3: PackedFloat32Array = _noise(0.3, 0.5, 7000.0, 1500.0)
					_mix(r3, _chime([base * 4.0, base * 5.3], 0.3, 0.3), 0)
					return r3
				"gravity_geode":
					var g3: PackedFloat32Array = _tone_sweep(0.6, base * 0.5, base * 2.5, "sine", 0.6, 0.02)
					_mix(g3, _whoosh(0.5, 3000.0, 300.0, 0.3), 0)
					return g3
				"stormspire":
					var s3: PackedFloat32Array = _zap(0.35, base * 1.5, 0.55)
					_mix(s3, _explosion(0.25, 0.35), 0)
					return s3
				"razor_prism":
					return _chime([base * 2.0, base * 2.5, base * 3.0], 0.3, 0.35)
				"quake_heart":
					var q3: PackedFloat32Array = _explosion(0.9, 0.9)
					_mix(q3, _tone_sweep(0.8, 60.0, 30.0, "sine", 0.6, 0.01), 0)
					return q3
				"gilded_idol":
					var g4: PackedFloat32Array = _arp([base, base * 1.26, base * 1.5, base * 2.0], 0.05, 0.6, "triangle", 0.3)
					_mix(g4, _sparkle(0.6, 0.3), 0)
					return g4
				"titanbane":
					var t3: PackedFloat32Array = _noise(0.4, 0.6, 3000.0, 400.0)
					_mix(t3, _horn(0.5, [base, base * 1.5], 0.35), 0)
					return t3
	return PackedFloat32Array()


func _gem(gem: String, kind: String, j: float) -> PackedFloat32Array:
	var f: float = float(GEM_BASE.get(gem, 440.0)) * j
	if kind == "attack":
		match gem:
			"ruby":
				var b: PackedFloat32Array = _noise(0.16, 0.5, 2200.0, 300.0)
				_mix(b, _tone_sweep(0.14, f * 1.5, f * 0.7, "saw", 0.3, 0.004), 0)
				return b
			"sapphire":
				return _zap(0.13, f * 2.0, 0.45)
			"emerald":
				return _tone_sweep(0.12, f * 1.6, f * 0.9, "sine", 0.5, 0.004)
			"topaz":
				var b: PackedFloat32Array = _tone_sweep(0.14, f, f * 0.5, "sine", 0.8, 0.002)
				_mix(b, _noise(0.06, 0.4, 1500.0, 200.0), 0)
				return b
			"amethyst":
				return _tone_sweep(0.06, f * 2.8, f * 1.1, "triangle", 0.45, 0.001)
			"aquamarine":
				return _chime([f * 2.0, f * 3.0], 0.18, 0.35)
			"opal":
				return _chime([f * 2.0, f * 2.5, f * 3.0], 0.22, 0.3)
			"diamond":
				return _chime([f, f * 2.76, f * 5.4], 0.16, 0.4)
	else:
		match gem:
			"ruby":
				return _explosion(0.18, 0.45)
			"sapphire":
				return _zap(0.09, f * 3.0, 0.3)
			"emerald":
				var b: PackedFloat32Array = _noise(0.1, 0.35, 1800.0, 400.0)
				_mix(b, _tone_sweep(0.08, f, f * 0.6, "sine", 0.3, 0.002), 0)
				return b
			"topaz":
				return _explosion(0.32, 0.7)
			"amethyst":
				return _noise(0.04, 0.4, 7000.0, 1500.0)
			"aquamarine":
				return _noise(0.12, 0.35, 9000.0, 3000.0)
			"opal":
				return _sparkle(0.14, 0.25)
			"diamond":
				return _chime([f * 1.5, f * 3.9, f * 6.1], 0.12, 0.35)
	return PackedFloat32Array()


func _enemy_death(arch: String, j: float) -> PackedFloat32Array:
	var base: float = {"normal": 300.0, "fast": 520.0, "armored": 160.0, "flying": 700.0, "swarm": 820.0,
		"arcane_resistant": 240.0, "regenerating": 360.0, "shielded": 200.0, "splitter": 180.0, "splitling": 900.0, "minion": 620.0}.get(arch, 300.0)
	var b: PackedFloat32Array = _tone_sweep(0.16, base * j, base * 0.4 * j, "triangle", 0.5, 0.002)
	_mix(b, _noise(0.12, 0.45, 3000.0 if arch != "armored" else 1200.0, 200.0), 0)
	if arch == "armored":
		_mix(b, _chime([base * 2.7, base * 4.1], 0.2, 0.25), 0)
	return b


## Появление врага: мягкий «вдох» портала, высота по архетипу.
func _enemy_spawn(arch: String, j: float) -> PackedFloat32Array:
	var base: float = _arch_base(arch)
	var b: PackedFloat32Array = _whoosh(0.22, base * 2.0 * j, base * 4.0 * j, 0.25)
	_mix(b, _tone_sweep(0.15, base * 0.8 * j, base * 1.2 * j, "sine", 0.2, 0.03), 0)
	return b


## Попадание по врагу: короткий глухой щелчок.
func _enemy_hurt(arch: String, j: float) -> PackedFloat32Array:
	var base: float = _arch_base(arch)
	var b: PackedFloat32Array = _tone_sweep(0.06, base * 1.4 * j, base * 0.7 * j, "triangle", 0.4, 0.001)
	_mix(b, _noise(0.04, 0.3, 2500.0 if arch != "armored" else 900.0, 400.0), 0)
	return b


func _arch_base(arch: String) -> float:
	return {"normal": 300.0, "fast": 520.0, "armored": 160.0, "flying": 700.0, "swarm": 820.0,
		"arcane_resistant": 240.0, "regenerating": 360.0, "shielded": 200.0, "splitter": 180.0, "splitling": 900.0, "minion": 620.0}.get(arch, 300.0)


func _reveal(q: int) -> PackedFloat32Array:
	var root: float = [523.0, 587.0, 659.0, 784.0, 880.0][clampi(q - 1, 0, 4)]
	var notes: Array[float] = [root]
	if q >= 2:
		notes.append(root * 1.5)
	if q >= 3:
		notes.append(root * 2.0)
	if q >= 4:
		notes.append(root * 2.5)
	if q >= 5:
		notes.append(root * 3.0)
	var crack: PackedFloat32Array = _noise(0.06, 0.6, 5000.0, 800.0)
	var b: PackedFloat32Array = _arp(notes, 0.05, 0.5 + 0.25 * float(q), "triangle", 0.35)
	_mix(b, crack, 0)
	if q >= 3:
		_mix(b, _sparkle(0.4 + 0.2 * float(q), 0.12 * float(q - 1)), int(0.08 * SR))
	if q >= 5:
		_mix(b, _whoosh(1.2, 200.0, 6000.0, 0.25), 0)
	return b


# --- Примитивы -------------------------------------------------------------

func _osc(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if fmod(phase, TAU) < PI else -1.0
		"saw":
			return fmod(phase, TAU) / PI - 1.0
		"triangle":
			var x: float = fmod(phase, TAU) / TAU
			return 4.0 * absf(x - 0.5) - 1.0
	return sin(phase)


func _env(t: float, dur: float, attack: float) -> float:
	var e: float = t / attack if t < attack else exp(-4.0 * (t - attack) / maxf(dur - attack, 0.001))
	var tail: float = clampf((dur - t) / 0.006, 0.0, 1.0)
	return e * tail


func _tone_sweep(dur: float, f0: float, f1: float, kind: String, amp: float, attack: float) -> PackedFloat32Array:
	var n: int = int(dur * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	var phase: float = 0.0
	for i: int in n:
		var t: float = float(i) / SR
		var f: float = lerpf(f0, f1, t / dur)
		phase += TAU * f / SR
		b[i] = _osc(kind, phase) * amp * _env(t, dur, attack)
	return b


func _noise(dur: float, amp: float, lp_from: float, lp_to: float) -> PackedFloat32Array:
	var n: int = int(dur * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	var y: float = 0.0
	for i: int in n:
		var t: float = float(i) / SR
		var fc: float = lerpf(lp_from, lp_to, t / dur)
		var alpha: float = 1.0 - exp(-TAU * fc / SR)
		y += alpha * (_rng.randf_range(-1.0, 1.0) - y)
		b[i] = y * amp * 1.6 * _env(t, dur, 0.002)
	return b


func _chime(freqs: Array, dur: float, amp: float) -> PackedFloat32Array:
	var n: int = int(dur * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	for k: int in freqs.size():
		var f: float = float(freqs[k])
		var a: float = amp / (1.0 + float(k) * 0.7)
		for i: int in n:
			var t: float = float(i) / SR
			b[i] += sin(TAU * f * t) * a * exp(-t * (5.0 + float(k) * 2.0) / dur) * clampf((dur - t) / 0.01, 0.0, 1.0)
	return _echo(b, 0.07, 0.25)


func _arp(notes: Array, step: float, dur: float, kind: String, amp: float) -> PackedFloat32Array:
	var n: int = int((dur + step * float(notes.size())) * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	for k: int in notes.size():
		var tone: PackedFloat32Array = _tone_sweep(dur * 0.8, float(notes[k]), float(notes[k]), kind, amp, 0.004)
		_mix(b, tone, int(step * float(k) * SR))
	return _echo(b, 0.11, 0.25)


func _whoosh(dur: float, f0: float, f1: float, amp: float) -> PackedFloat32Array:
	var n: int = int(dur * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	var y: float = 0.0
	for i: int in n:
		var t: float = float(i) / SR
		var fc: float = lerpf(f0, f1, t / dur)
		var alpha: float = 1.0 - exp(-TAU * fc / SR)
		y += alpha * (_rng.randf_range(-1.0, 1.0) - y)
		var e: float = sin(PI * clampf(t / dur, 0.0, 1.0))
		b[i] = y * amp * 2.0 * e
	return b


func _buzz(dur: float, f: float, amp: float) -> PackedFloat32Array:
	var n: int = int(dur * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	var phase: float = 0.0
	for i: int in n:
		var t: float = float(i) / SR
		phase += TAU * (f + sin(t * TAU * 30.0) * 12.0) / SR
		b[i] = (_osc("square", phase) * 0.6 + _osc("saw", phase * 1.01) * 0.4) * amp * _env(t, dur, 0.004)
	return b


func _zap(dur: float, f: float, amp: float) -> PackedFloat32Array:
	var n: int = int(dur * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	var phase: float = 0.0
	var jitter: float = 0.0
	for i: int in n:
		var t: float = float(i) / SR
		if i % 220 == 0:
			jitter = _rng.randf_range(-0.4, 0.4)
		phase += TAU * f * (1.0 + jitter) / SR
		b[i] = (_osc("square", phase) * 0.5 + _rng.randf_range(-0.5, 0.5)) * amp * _env(t, dur, 0.002)
	return b


func _explosion(dur: float, amp: float) -> PackedFloat32Array:
	var b: PackedFloat32Array = _noise(dur, amp, 1800.0, 60.0)
	_mix(b, _tone_sweep(dur * 0.8, 90.0, 35.0, "sine", amp * 0.9, 0.003), 0)
	return b


func _horn(dur: float, freqs: Array, amp: float) -> PackedFloat32Array:
	var n: int = int(dur * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	for f: Variant in freqs:
		var phase: float = 0.0
		for i: int in n:
			var t: float = float(i) / SR
			phase += TAU * float(f) * (1.0 + sin(t * TAU * 5.0) * 0.004) / SR
			var e: float = clampf(t / (dur * 0.25), 0.0, 1.0) * clampf((dur - t) / (dur * 0.35), 0.0, 1.0)
			b[i] += _osc("saw", phase) * amp / float(freqs.size()) * e
	return _lowpass(b, 900.0)


func _sparkle(dur: float, amp: float) -> PackedFloat32Array:
	var n: int = int(dur * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	var count: int = int(dur * 18.0)
	for k: int in count:
		var start: int = _rng.randi_range(0, maxi(n - int(0.08 * SR), 1))
		var f: float = _rng.randf_range(2500.0, 6000.0)
		var ping: PackedFloat32Array = _tone_sweep(0.07, f, f, "sine", amp * _rng.randf_range(0.3, 1.0), 0.001)
		_mix(b, ping, start)
	return b


func _lowpass(b: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var alpha: float = 1.0 - exp(-TAU * fc / SR)
	var y: float = 0.0
	for i: int in b.size():
		y += alpha * (b[i] - y)
		b[i] = y
	return b


func _echo(b: PackedFloat32Array, delay: float, feedback: float) -> PackedFloat32Array:
	var d: int = int(delay * SR)
	var out: PackedFloat32Array = b.duplicate()
	out.resize(b.size() + d * 3)
	for i: int in range(d, out.size()):
		out[i] += out[i - d] * feedback
	return out


func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int) -> void:
	if dst.size() < offset + src.size():
		dst.resize(offset + src.size())
	for i: int in src.size():
		dst[offset + i] += src[i]


func _save(buf: PackedFloat32Array, path: String, rate: int = SR) -> void:
	var peak: float = 0.0
	for x: float in buf:
		peak = maxf(peak, absf(x))
	var gain: float = 0.89 / peak if peak > 0.89 else 1.0
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i: int in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	var err: Error = w.save_to_wav(path)
	if err != OK:
		push_error("не удалось сохранить %s: %s" % [path, error_string(err)])
