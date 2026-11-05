class_name Hud
extends Control
## Сборка HUD: верхняя панель, превью волны и журнал, фазовая панель, панель башни, баннер, тосты.

const T := preload("res://ui/theme/ui_tokens.gd")
const MARGIN: float = 16.0

var top: TopBar
var wave_panel: WavePanel
var phase: PhaseBar
var tower_panel: TowerPanel
var banner: Banner
var toasts: ToastLayer
var tracker: RecipeTracker
var boss_bar: BossBar
var captions: SoundCaptions
var forecast: WaveForecast
var coins: CoinFlight


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ThemeBuilder.get_theme()

	banner = Banner.new()
	add_child(banner)

	top = TopBar.new()
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = MARGIN
	top.offset_right = -MARGIN
	top.offset_top = MARGIN

	wave_panel = WavePanel.new()
	add_child(wave_panel)
	wave_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	wave_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wave_panel.offset_right = -MARGIN
	wave_panel.offset_top = 104

	tracker = RecipeTracker.new()
	tracker.avoid = wave_panel
	add_child(tracker)
	tracker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tracker.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tracker.offset_right = -MARGIN
	tracker.offset_bottom = -MARGIN

	phase = PhaseBar.new()
	add_child(phase)
	phase.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	phase.grow_vertical = Control.GROW_DIRECTION_BEGIN
	phase.offset_bottom = -MARGIN
	phase.offset_left = 340
	phase.offset_right = -340

	# Панель башни — после фазовой панели: при крупном масштабе UI она шире отступа 340 и иначе
	# пряталась бы под ней (трекер остаётся под фазовой панелью: поверх он закрыл бы «Начать волну»).
	tower_panel = TowerPanel.new()
	add_child(tower_panel)
	tower_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	tower_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tower_panel.offset_left = MARGIN
	tower_panel.offset_bottom = -MARGIN
	tower_panel.visible = false

	boss_bar = BossBar.new()
	add_child(boss_bar)
	boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_bar.offset_top = 96

	forecast = WaveForecast.new()
	add_child(forecast)
	forecast.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	forecast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	forecast.offset_right = -MARGIN - 340
	forecast.offset_top = 104

	captions = SoundCaptions.new()
	add_child(captions)
	captions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	captions.offset_left = MARGIN
	captions.offset_top = 40

	toasts = ToastLayer.new()
	add_child(toasts)
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.offset_top = 112

	coins = CoinFlight.new()
	add_child(coins)


func show_tower(sim: GameSim, t: TowerState) -> void:
	var was: bool = tower_panel.visible
	tower_panel.show_tower(sim, t)
	tower_panel.visible = true
	if not was:
		# Только прозрачность: высота панели пересчитывается после показа (TowerPanel._fit),
		# а сдвиг анимации запомнил бы позицию до пересчёта и увёл бы панель за низ экрана.
		Ui.pop_in(tower_panel, 0.0, Vector2.ZERO)
		Audio.play("sfx/ui/panel_open")


func show_slate(sim: GameSim, s: TowerState) -> void:
	var was: bool = tower_panel.visible
	tower_panel.show_slate(sim, s)
	tower_panel.visible = true
	if not was:
		Ui.pop_in(tower_panel, 0.0, Vector2.ZERO)
		Audio.play("sfx/ui/panel_open")


func show_wall(sim: GameSim, cell: Vector2i) -> void:
	var was: bool = tower_panel.visible
	tower_panel.show_wall(sim, cell)
	tower_panel.visible = true
	if not was:
		# Только прозрачность: высота панели пересчитывается после показа (TowerPanel._fit),
		# а сдвиг анимации запомнил бы позицию до пересчёта и увёл бы панель за низ экрана.
		Ui.pop_in(tower_panel, 0.0, Vector2.ZERO)
		Audio.play("sfx/ui/panel_open")


func hide_tower() -> void:
	if tower_panel.visible:
		Audio.play("sfx/ui/panel_close")
	tower_panel.visible = false
	tower_panel.tower_id = -1
	tower_panel.wall_cell = Vector2i(-1, -1)
