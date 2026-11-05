extends TestCase
## Учёт голосов Audio (VoicePool): свободные голоса без перебора пула, счётчики по событию,
## приоритет важных звуков над боевыми. Плееры тестовые, вне дерева — звук не воспроизводится.

const SIZE: int = 6


func _pool() -> VoicePool:
	var list: Array[AudioStreamPlayer] = []
	for i: int in SIZE:
		list.append(AudioStreamPlayer.new())
	return VoicePool.new(list)


func _free_players(vp: VoicePool) -> void:
	for p: AudioStreamPlayer in vp.players:
		p.free()


func _fill(vp: VoicePool, id: String) -> Array[AudioStreamPlayer]:
	var taken: Array[AudioStreamPlayer] = []
	while true:
		var p: AudioStreamPlayer = vp.take(id)
		if p == null:
			break
		vp.claim(p, id)
		taken.append(p)
	return taken


func test_combat_sounds_skip_when_pool_is_full() -> void:
	var vp: VoicePool = _pool()
	assert_eq(_fill(vp, "sfx/gems/ruby/impact").size(), SIZE, "боевой звук занимает весь пул")
	assert_eq(vp.active("sfx/gems/ruby/impact"), SIZE)
	assert_true(vp.take("sfx/enemies/normal/hurt") == null, "ещё один боевой звук пропускается")
	_free_players(vp)


func test_important_sound_steals_oldest_combat_voice() -> void:
	var vp: VoicePool = _pool()
	var first: AudioStreamPlayer = vp.take("sfx/game/life_lost")
	vp.claim(first, "sfx/game/life_lost")
	var combat: Array[AudioStreamPlayer] = _fill(vp, "sfx/enemies/fast/hurt")
	assert_eq(combat.size(), SIZE - 1)
	var p: AudioStreamPlayer = vp.take("sfx/waves/clear")
	assert_true(p == combat[0], "забирается самый старый боевой голос, а не звук потери жизни")
	assert_eq(vp.active("sfx/enemies/fast/hurt"), SIZE - 2)
	assert_eq(vp.active("sfx/game/life_lost"), 1)
	_free_players(vp)


func test_release_returns_voice_once() -> void:
	var vp: VoicePool = _pool()
	var p: AudioStreamPlayer = vp.take("sfx/ui/click")
	vp.claim(p, "sfx/ui/click")
	assert_eq(vp.free_count(), SIZE - 1)
	vp.release(p)
	vp.release(p)
	assert_eq(vp.free_count(), SIZE, "повторный finished не дублирует голос")
	assert_eq(vp.active("sfx/ui/click"), 0)
	assert_eq(vp.busy_count(), 0)
	vp.claim(vp.take("sfx/ui/click"), "sfx/ui/click")
	vp.reset()
	assert_eq(vp.free_count(), SIZE, "reset возвращает все голоса")
	_free_players(vp)


func test_combat_event_classes() -> void:
	for id: String in ["sfx/gems/ruby/attack", "sfx/specials/stormspire/impact", "sfx/enemies/swarm/death", "sfx/status/crit", "sfx/traits/blink"]:
		assert_true(VoicePool.is_combat_event(id), id)
	for id2: String in ["sfx/ui/click", "sfx/game/life_lost", "sfx/boss/spawn", "sfx/waves/start", "sfx/economy/mvp", "music/combat"]:
		assert_false(VoicePool.is_combat_event(id2), id2)
