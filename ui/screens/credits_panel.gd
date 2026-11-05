class_name CreditsPanel
extends Modal
## Авторы и лицензии сторонних материалов. Кнопка «Лицензии» открывает полные тексты:
## OFL шрифтов, MIT Godot и лицензии сторонних библиотек внутри движка.

const LICENSE_FILES: Array[String] = ["res://assets/fonts/Inter_OFL.txt", "res://assets/fonts/Cormorant_OFL.txt",
	"res://assets/fonts/CormorantSC_OFL.txt", "res://assets/ui/icons/LUCIDE_LICENSE.txt"]
## Сколько высоты окна оставить под заголовок, строку версии и поля, когда разделы прокручиваются.
const CHROME_HEIGHT: float = 220.0

var _scroll: ScrollContainer
var _sections: VBoxContainer


func _init() -> void:
	super._init()
	header(tr("CREDITS_TITLE"), "info")
	# Разделы прокручиваются: при крупном масштабе интерфейса окно выше экрана.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_sections = Ui.vbox(T.SP_3)
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_sections)
	var lines: Array[Array] = [
		["CREDITS_GAME", "CREDITS_GAME_TEXT"],
		["CREDITS_REMAKE", "CREDITS_REMAKE_TEXT"],
		["CREDITS_ENGINE", "CREDITS_ENGINE_TEXT"],
		["CREDITS_FONTS", "CREDITS_FONTS_TEXT"],
		["CREDITS_MODELS", "CREDITS_MODELS_TEXT"],
		["CREDITS_AUDIO", "CREDITS_AUDIO_TEXT"],
		["CREDITS_INSPIRATION", "CREDITS_INSPIRATION_TEXT"],
	]
	for pair: Array in lines:
		_sections.add_child(Ui.label(tr(String(pair[0])), "CapsLabel"))
		var l: Label = Ui.label(tr(String(pair[1])), "BodyLabel", true)
		l.custom_minimum_size = Vector2(560, 0)
		_sections.add_child(l)
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	row.add_child(Ui.label("v%s · Godot %s" % [Game.version(), Engine.get_version_info()["string"]], "FaintLabel"))
	row.add_child(Ui.spacer())
	var lic: Button = Ui.button(tr("CREDITS_LICENSES"), "GhostButton")
	lic.pressed.connect(func() -> void: add_child(_licenses_modal()))
	row.add_child(lic)
	body.add_child(row)


func _ready() -> void:
	super._ready()
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()


## Высота разделов — по содержимому, но не выше окна (в координатах интерфейса, с учётом масштаба).
func _fit() -> void:
	if not is_inside_tree():
		return
	var need: Vector2 = _sections.get_combined_minimum_size()
	var room: float = maxf(200.0, get_viewport_rect().size.y - CHROME_HEIGHT)
	_scroll.custom_minimum_size = Vector2(need.x, minf(need.y, room))


func _licenses_modal() -> Modal:
	var m: Modal = Modal.new()
	m.header(tr("CREDITS_LICENSES"), "info")
	var te: TextEdit = TextEdit.new()
	te.editable = false
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.custom_minimum_size = Vector2(760, 520)
	te.text = license_text()
	m.body.add_child(te)
	return m


## Полный текст лицензий: собственные сторонние файлы проекта, затем движок и его компоненты.
static func license_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("Gem Tower Defense %s\n\n%s" % [Game.version(), "\n".join(third_party_rows())])
	for path: String in LICENSE_FILES:
		if FileAccess.file_exists(path):
			parts.append("=== %s ===\n%s" % [path.get_file(), FileAccess.get_file_as_string(path).strip_edges()])
	parts.append("=== Godot Engine ===\n%s" % Engine.get_license_text().strip_edges())
	var comp: PackedStringArray = PackedStringArray()
	for c: Dictionary in Engine.get_copyright_info():
		for p: Dictionary in c["parts"]:
			comp.append("- %s: %s (%s)" % [c["name"], ", ".join(PackedStringArray(p["copyright"])), p["license"]])
	parts.append("=== Third-party components in Godot Engine ===\n%s" % "\n".join(comp))
	var lic: Dictionary = Engine.get_license_info()
	for lic_name: String in lic:
		parts.append("=== %s ===\n%s" % [lic_name, String(lic[lic_name]).strip_edges()])
	return "\n\n".join(parts)


## Строки таблицы assets/LICENSES.md («| файл | автор | лицензия | источник |») в виде списка.
static func third_party_rows() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not FileAccess.file_exists("res://assets/LICENSES.md"):
		return out
	for line: String in FileAccess.get_file_as_string("res://assets/LICENSES.md").split("\n"):
		var cells: PackedStringArray = line.strip_edges().trim_prefix("|").trim_suffix("|").split("|")
		if not line.begins_with("|") or cells.size() < 4 or cells[0].strip_edges() in ["Файл", ""] or cells[0].begins_with("-"):
			continue
		var c: PackedStringArray = PackedStringArray()
		for cell: String in cells:
			c.append(cell.strip_edges().replace("`", ""))
		out.append("• %s — %s — %s (%s)" % [c[0], c[1], c[2], c[3]])
	return out
