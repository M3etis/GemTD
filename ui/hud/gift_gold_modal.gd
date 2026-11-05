class_name GiftGoldModal
extends Modal
## «Гонка»: передать сопернику часть своего золота — ползунок и быстрые суммы.

signal gift(amount: int)

const QUICK: Array[int] = [10, 25, 50, 100]

var _slider: HSlider
var _value: Label
var _ok: Button


func setup(player: String, gold: int) -> GiftGoldModal:
	header(tr("MP_GIFT_TITLE") % player, "coin")
	var info: Label = Ui.label(tr("MP_GIFT_HAVE") % gold, "DimLabel", true)
	info.custom_minimum_size = Vector2(420, 0)
	body.add_child(info)
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	_slider = HSlider.new()
	_slider.min_value = 1
	_slider.max_value = maxi(gold, 1)
	_slider.step = 1
	_slider.value = clampi(mini(25, gold), 1, maxi(gold, 1))
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size = Vector2(320, 24)
	_slider.value_changed.connect(func(_v: float) -> void: _sync())
	row.add_child(_slider)
	_value = Ui.label("", "NumberLabel")
	_value.custom_minimum_size = Vector2(64, 0)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value.add_theme_color_override("font_color", T.GOLD)
	row.add_child(_value)
	body.add_child(row)
	var quick: HBoxContainer = Ui.hbox(4)
	for v: int in QUICK:
		if v < gold:
			quick.add_child(_chip(str(v), v))
	if gold >= 2:
		quick.add_child(_chip(tr("MP_GIFT_HALF"), gold / 2))
	quick.add_child(_chip(tr("MP_GIFT_ALL"), gold))
	body.add_child(quick)
	var actions: HBoxContainer = Ui.hbox(T.SP_3)
	actions.alignment = BoxContainer.ALIGNMENT_END
	var cancel: Button = Ui.button(tr("ACT_CANCEL"), "GhostButton")
	cancel.pressed.connect(close)
	actions.add_child(cancel)
	_ok = Ui.button("", "PrimaryButton")
	_ok.disabled = gold <= 0
	_ok.pressed.connect(func() -> void:
		var amount: int = int(_slider.value)
		close()
		gift.emit(amount))
	actions.add_child(_ok)
	body.add_child(actions)
	_sync()
	return self


func _chip(text: String, amount: int) -> Button:
	var b: Button = Button.new()
	b.theme_type_variation = "ChipButton"
	b.text = text
	Ui.attach_feedback(b)
	# После attach_feedback (он включает фокус): Enter/Space остаются у кнопки «Передать».
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: _slider.value = amount)
	return b


func _sync() -> void:
	_value.text = str(int(_slider.value))
	_ok.text = tr("MP_GIFT_SEND") % int(_slider.value)
