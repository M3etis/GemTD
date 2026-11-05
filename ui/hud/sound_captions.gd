class_name SoundCaptions
extends VBoxContainer
## Визуальные подсказки к звукам (доступность, §8.6): важные звуковые события дублируются подписью.
## Включаются в Настройки → Доступность.

const T := preload("res://ui/theme/ui_tokens.gd")
const LIFETIME: float = 2.6
const CAPTIONS: Dictionary = {
	"sfx/boss/warning": ["CAP_BOSS_WARNING", "boss"], "sfx/boss/spawn": ["CAP_BOSS_SPAWN", "boss"],
	"sfx/boss/phase_change": ["CAP_BOSS_PHASE", "boss"], "sfx/boss/summon": ["CAP_BOSS_SUMMON", "boss"],
	"sfx/boss/death": ["CAP_BOSS_DEATH", "crown"], "sfx/waves/start": ["CAP_WAVE_START", "play"],
	"sfx/waves/air_warning": ["CAP_AIR", "air"], "sfx/waves/clear": ["CAP_WAVE_CLEAR", "check"],
	"sfx/waves/perfect": ["CAP_WAVE_PERFECT", "check"], "sfx/game/life_lost": ["CAP_LIFE_LOST", "heart"],
	"sfx/economy/gold_stolen": ["CAP_GOLD_STOLEN", "coin"], "sfx/traits/disarm": ["CAP_DISARM", "close"],
	"sfx/economy/mvp": ["CAP_MVP", "crown"], "sfx/game/victory": ["CAP_VICTORY", "trophy"],
	"sfx/game/defeat": ["CAP_DEFEAT", "skull"], "sfx/game/new_record": ["CAP_RECORD", "trophy"],
	"sfx/net/player_joined": ["CAP_PLAYER_JOINED", "arrow_up"], "sfx/net/player_left": ["CAP_PLAYER_LEFT", "close"],
	"sfx/net/opponent_eliminated": ["CAP_OPPONENT_OUT", "skull"], "sfx/choose/forge_onehit": ["CAP_FORGE", "sparkle"],
	"sfx/choose/forge_collect": ["CAP_FORGE", "sparkle"], "sfx/build/reveal/q4": ["CAP_RARE", "gem"],
	"sfx/build/reveal/q5": ["CAP_RARE", "gem"],
}

var _last: Dictionary = {}
## Настройка кешируется: сигнал приходит на каждый звук (сотни раз в кадр в большом бою).
var _enabled: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_enabled = bool(Settings.get_value("accessibility", "sound_captions"))
	Events.settings_changed.connect(func(section: String) -> void:
		if section == "accessibility":
			_enabled = bool(Settings.get_value("accessibility", "sound_captions")))
	Audio.played.connect(_on_played)


func _on_played(id: String) -> void:
	if not _enabled or not CAPTIONS.has(id):
		return
	var key: String = String(CAPTIONS[id][0])
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(key, -10.0)) < 1.5:
		return
	_last[key] = now
	var p: PanelContainer = Ui.panel("ChipPanel", false)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = Ui.hbox(T.SP_2)
	row.add_child(Ui.icon("sound", 14, T.TEXT_DIM))
	row.add_child(Ui.icon(String(CAPTIONS[id][1]), 14, T.ACCENT))
	row.add_child(Ui.label(tr(key), "BodyLabel"))
	p.add_child(row)
	add_child(p)
	var tw: Tween = p.create_tween()
	tw.tween_interval(LIFETIME)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
	while get_child_count() > 4:
		var old: Node = get_child(0)
		remove_child(old)
		old.queue_free()
