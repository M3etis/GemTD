class_name ToastLayer
extends VBoxContainer
## Всплывающие уведомления (сверху по центру).

const T := preload("res://ui/theme/ui_tokens.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", T.SP_2)
	Events.toast_requested.connect(show_toast)


func show_toast(text: String, kind: String = "info") -> void:
	var color: Color = {"info": T.ACCENT, "error": T.DANGER, "success": T.SUCCESS, "gold": T.GOLD, "warning": T.WARNING, "hint": T.ACCENT}.get(kind, T.ACCENT)
	var icon_name: String = {"info": "info", "error": "close", "success": "check", "gold": "coin", "warning": "info", "hint": "sparkle"}.get(kind, "info")
	var p: PanelContainer = Ui.panel("GlassPanel")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row: HBoxContainer = Ui.hbox(T.SP_2)
	row.add_child(Ui.icon(icon_name, 16, color))
	var l: Label = Ui.label(text, "BodyLabel", kind == "hint")
	if kind == "hint":
		l.custom_minimum_size = Vector2(520, 0)
	row.add_child(l)
	p.add_child(row)
	add_child(p)
	Audio.play("sfx/ui/error" if kind == "error" else "sfx/ui/toast")
	p.modulate.a = 0.0
	var tw: Tween = p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, T.dur(T.T_BASE))
	# Подсказки живут дольше: их нужно успеть прочитать.
	tw.tween_interval(7.0 if kind == "hint" else (2.2 if kind != "error" else 1.6))
	tw.tween_property(p, "modulate:a", 0.0, T.dur(T.T_SLOW))
	tw.tween_callback(p.queue_free)
	while get_child_count() > 4:
		get_child(0).queue_free()
		remove_child(get_child(0))
