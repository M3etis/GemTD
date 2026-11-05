class_name MusicSynth
extends RefCounted
## Процедурная музыка встроенного пака (music/*): тёмный фэнтези-эмбиент в ре миноре.
## Зацикленные треки рендерятся «по кругу»: хвосты нот после конца буфера переносятся в начало,
## поэтому шов петли не слышен. Частота 22 050 Гц, моно — достаточно для фоновой музыки и экономит место.

const SR: int = 22050
const NAMES: Array[String] = ["menu", "build", "combat", "boss", "victory", "defeat"]
## Треки, которые играют один раз (остальные зациклены).
const ONE_SHOT: Array[String] = ["victory", "defeat"]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _len: int = 0
var _loop: bool = true


static func is_loop(id: String) -> bool:
	return not ONE_SHOT.has(id)


static func midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


func render(id: String) -> PackedFloat32Array:
	_rng.seed = hash(id) + 17
	_loop = is_loop(id)
	match id:
		"menu":
			return _menu()
		"build":
			return _build()
		"combat":
			return _combat()
		"boss":
			return _boss()
		"victory":
			return _victory()
		"defeat":
			return _defeat()
	return PackedFloat32Array()


# --- Треки --------------------------------------------------------------------

func _menu() -> PackedFloat32Array:
	var beat: float = 60.0 / 66.0
	var bar: float = beat * 4.0
	var b: PackedFloat32Array = _buffer(bar * 8.0)
	var chords: Array = [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 49, 52]]
	for i: int in 4:
		_pad(b, chords[i], float(i) * bar * 2.0, bar * 2.0, 0.09, 1.2)
		_note(b, "drone", midi(chords[i][0] - 12), float(i) * bar * 2.0, bar * 2.0, 0.07)
	var scale: Array[int] = [62, 65, 67, 69, 72, 74, 77]
	for k: int in 14:
		var at: float = float(k) * bar * 8.0 / 14.0 + _rng.randf_range(0.0, beat)
		_note(b, "bell", midi(scale[_rng.randi_range(0, scale.size() - 1)]), at, 2.5, 0.05)
	return _finish(b, 0.9)


func _build() -> PackedFloat32Array:
	var beat: float = 60.0 / 84.0
	var bar: float = beat * 4.0
	var b: PackedFloat32Array = _buffer(bar * 8.0)
	var chords: Array = [[50, 53, 57], [53, 57, 60], [48, 52, 55], [43, 46, 50]]
	for i: int in 8:
		var ch: Array = chords[i % 4]
		var t0: float = float(i) * bar
		_pad(b, ch, t0, bar, 0.06, 0.9)
		_note(b, "bass", midi(int(ch[0]) - 12), t0, beat * 1.5, 0.12)
		for s: int in 8:
			var n: int = int(ch[s % 3]) + (12 if s >= 4 else 0)
			_note(b, "pluck", midi(n), t0 + float(s) * beat * 0.5, 0.6, 0.045 + 0.02 * float(s == 0))
	return _finish(b, 0.85)


func _combat() -> PackedFloat32Array:
	var beat: float = 60.0 / 112.0
	var bar: float = beat * 4.0
	var b: PackedFloat32Array = _buffer(bar * 8.0)
	var chords: Array = [[50, 53, 57], [46, 50, 53], [48, 52, 55], [45, 49, 52]]
	for i: int in 8:
		var ch: Array = chords[int(i / 2.0) % 4]
		var t0: float = float(i) * bar
		_pad(b, ch, t0, bar, 0.04, 0.6)
		for e: int in 8:
			_note(b, "bass", midi(int(ch[0]) - 12 + (12 if e % 4 == 3 else 0)), t0 + float(e) * beat * 0.5, beat * 0.42, 0.11)
			_drum(b, "hat", t0 + float(e) * beat * 0.5, 0.025 if e % 2 == 0 else 0.018)
		for k: int in 4:
			if k % 2 == 0:
				_drum(b, "kick", t0 + float(k) * beat, 0.32)
			else:
				_drum(b, "snare", t0 + float(k) * beat, 0.13)
		for s: int in 16:
			if _rng.randf() < 0.55:
				_note(b, "pluck", midi(int(ch[s % 3]) + 12), t0 + float(s) * beat * 0.25, 0.3, 0.03)
	return _finish(b, 0.8)


func _boss() -> PackedFloat32Array:
	var beat: float = 60.0 / 128.0
	var bar: float = beat * 4.0
	var b: PackedFloat32Array = _buffer(bar * 8.0)
	var roots: Array[int] = [38, 39, 38, 37, 38, 39, 46, 45]
	for i: int in 8:
		var r: int = roots[i]
		var t0: float = float(i) * bar
		_pad(b, [r + 12, r + 15, r + 19], t0, bar, 0.035, 0.3)
		_note(b, "drone", midi(r - 12), t0, bar, 0.09)
		for e: int in 8:
			_note(b, "bass", midi(r + (12 if e == 6 else 0)), t0 + float(e) * beat * 0.5, beat * 0.4, 0.13)
			_drum(b, "hat", t0 + float(e) * beat * 0.5, 0.02)
		for k: int in 4:
			_drum(b, "kick", t0 + float(k) * beat, 0.36)
			if k % 2 == 1:
				_drum(b, "snare", t0 + float(k) * beat, 0.16)
		if i == 7:
			for f: int in 4:
				_drum(b, "tom", t0 + bar * 0.5 + float(f) * beat * 0.5, 0.2)
		_note(b, "stab", midi(r + 24), t0 + beat * 2.5, 0.25, 0.06)
	return _finish(b, 0.85)


func _victory() -> PackedFloat32Array:
	var b: PackedFloat32Array = _buffer(6.5)
	var notes: Array[int] = [62, 66, 69, 74, 78, 81]
	for i: int in notes.size():
		_note(b, "brass", midi(notes[i]), float(i) * 0.16, 0.9 - float(i) * 0.05, 0.07)
	_pad(b, [62, 66, 69, 74], 0.9, 5.0, 0.08, 0.6)
	_note(b, "bell", midi(86), 1.0, 3.0, 0.06)
	_drum(b, "kick", 0.9, 0.25)
	return _finish(b, 0.9)


func _defeat() -> PackedFloat32Array:
	var b: PackedFloat32Array = _buffer(6.5)
	var chords: Array = [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 48, 52]]
	for i: int in 4:
		_pad(b, chords[i], float(i) * 1.3, 2.4, 0.08, 0.7)
	_note(b, "drone", midi(26), 0.0, 6.0, 0.1)
	_drum(b, "tom", 0.0, 0.25)
	_drum(b, "tom", 5.2, 0.2)
	return _finish(b, 0.9)


# --- Инструменты ---------------------------------------------------------------

func _buffer(seconds: float) -> PackedFloat32Array:
	_len = int(seconds * SR)
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(_len)
	return b


## Добавляет сэмпл; в зацикленном треке хвост после конца переносится в начало.
func _put(b: PackedFloat32Array, i: int, v: float) -> void:
	if i < _len:
		b[i] += v
	elif _loop:
		b[i % _len] += v


## Пэд: каждая нота — три расстроенных треугольника с медленной атакой и затуханием.
func _pad(b: PackedFloat32Array, notes: Array, start: float, dur: float, amp: float, attack: float) -> void:
	for n: Variant in notes:
		var f: float = midi(float(n))
		for d: float in [-0.12, 0.0, 0.11]:
			_voice(b, f * pow(2.0, d / 12.0), start, dur, amp / 3.0, attack, 1.2, "tri")


func _voice(b: PackedFloat32Array, f: float, start: float, dur: float, amp: float, attack: float, release: float, kind: String) -> void:
	var s0: int = int(start * SR)
	var total: int = int((dur + release) * SR)
	var phase: float = _rng.randf() * TAU
	var step: float = TAU * f / float(SR)
	var lp: float = 0.0
	for i: int in total:
		var t: float = float(i) / SR
		var env: float = minf(t / attack, 1.0) if t < dur else maxf(0.0, 1.0 - (t - dur) / release)
		var x: float
		if kind == "tri":
			var u: float = fmod(phase, TAU) / TAU
			x = 4.0 * absf(u - 0.5) - 1.0
		else:
			x = fmod(phase, TAU) / PI - 1.0
		lp += 0.18 * (x - lp)
		phase += step
		_put(b, s0 + i, lp * env * amp)


func _note(b: PackedFloat32Array, kind: String, f: float, start: float, dur: float, amp: float) -> void:
	var s0: int = int(start * SR)
	var n: int = int(dur * SR)
	var phase: float = 0.0
	var step: float = TAU * f / float(SR)
	match kind:
		"pluck":
			# Карплюс — Стронг: буфер шума, затухающий фильтр.
			var period: int = maxi(2, int(float(SR) / f))
			var ring: PackedFloat32Array = PackedFloat32Array()
			ring.resize(period)
			for k: int in period:
				ring[k] = _rng.randf_range(-1.0, 1.0)
			var idx: int = 0
			for i: int in n:
				var a: float = ring[idx]
				var nxt: float = ring[(idx + 1) % period]
				ring[idx] = (a + nxt) * 0.497
				idx = (idx + 1) % period
				_put(b, s0 + i, a * amp)
		"bell":
			for i: int in n:
				var t: float = float(i) / SR
				var env: float = exp(-2.2 * t) * minf(t / 0.004, 1.0)
				_put(b, s0 + i, (sin(phase) + 0.4 * sin(phase * 2.76) + 0.2 * sin(phase * 5.4)) * env * amp)
				phase += step
		"bass":
			for i: int in n:
				var t: float = float(i) / SR
				var env: float = minf(t / 0.01, 1.0) * clampf((dur - t) / 0.03, 0.0, 1.0)
				var x: float = sin(phase) + 0.3 * sin(phase * 2.0)
				_put(b, s0 + i, tanh(x * 1.5) * env * amp)
				phase += step
		"drone":
			for i: int in n:
				var t: float = float(i) / SR
				var env: float = minf(t / 1.0, 1.0) * clampf((dur - t) / 1.0, 0.0, 1.0)
				_put(b, s0 + i, (sin(phase) + 0.5 * sin(phase * 1.5)) * env * amp)
				phase += step
		"stab", "brass":
			var lp: float = 0.0
			var cutoff: float = 0.12 if kind == "stab" else 0.08
			for i: int in n:
				var t: float = float(i) / SR
				var env: float = minf(t / (0.005 if kind == "stab" else 0.06), 1.0) * exp(-(3.0 if kind == "stab" else 1.2) * t)
				var x: float = fmod(phase, TAU) / PI - 1.0
				lp += cutoff * (x - lp)
				_put(b, s0 + i, lp * env * amp * 2.0)
				phase += step


func _drum(b: PackedFloat32Array, kind: String, start: float, amp: float) -> void:
	var s0: int = int(start * SR)
	match kind:
		"kick":
			var phase: float = 0.0
			for i: int in int(0.28 * SR):
				var t: float = float(i) / SR
				var f: float = 45.0 + 85.0 * exp(-t * 28.0)
				phase += TAU * f / float(SR)
				_put(b, s0 + i, sin(phase) * exp(-t * 9.0) * amp)
		"snare":
			var phase2: float = 0.0
			for i: int in int(0.18 * SR):
				var t: float = float(i) / SR
				phase2 += TAU * 185.0 / float(SR)
				_put(b, s0 + i, (_rng.randf_range(-1.0, 1.0) * 0.8 + sin(phase2) * 0.5) * exp(-t * 18.0) * amp)
		"hat":
			var prev: float = 0.0
			for i: int in int(0.05 * SR):
				var t: float = float(i) / SR
				var x: float = _rng.randf_range(-1.0, 1.0)
				_put(b, s0 + i, (x - prev) * exp(-t * 60.0) * amp)
				prev = x
		"tom":
			var phase3: float = 0.0
			for i: int in int(0.4 * SR):
				var t: float = float(i) / SR
				phase3 += TAU * (70.0 + 40.0 * exp(-t * 10.0)) / float(SR)
				_put(b, s0 + i, sin(phase3) * exp(-t * 6.0) * amp)


## Мягкое ограничение и нормализация.
func _finish(b: PackedFloat32Array, level: float) -> PackedFloat32Array:
	var peak: float = 0.0001
	for i: int in b.size():
		b[i] = tanh(b[i] * 1.2)
		peak = maxf(peak, absf(b[i]))
	var g: float = level / peak
	var fade_out: int = int(0.5 * SR)
	for i2: int in b.size():
		b[i2] *= g
		if not _loop:
			# Разовые треки: короткое нарастание и плавное затухание без щелчка в конце.
			b[i2] *= minf(float(i2) / (0.005 * SR), 1.0) * minf(float(b.size() - i2) / float(fade_out), 1.0)
	return b
