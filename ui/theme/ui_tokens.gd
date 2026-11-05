class_name UiTokens
extends RefCounted
## Дизайн-токены: единственное место, где заданы цвета, шрифты, отступы и тайминги UI (§8.2).

## Палитра A «Обсидиановая сокровищница» (ART_DIRECTION.md §3): чернильное стекло, латунь, лёд.
const BG: Color = Color("07080d")
const SURFACE: Color = Color("0e1119")
const SURFACE_HI: Color = Color("171b26")
const SURFACE_LOW: Color = Color("0a0c12")
const BORDER: Color = Color(0.79, 0.64, 0.36, 0.2)
const BORDER_STRONG: Color = Color(0.79, 0.64, 0.36, 0.55)
const GLASS_BORDER: Color = Color("4a3f2c")
const BRASS: Color = Color("c9a45c")
const TEXT: Color = Color("ece7dc")
const TEXT_DIM: Color = Color("a29d93")
## Контраст ≥4.5:1 на SURFACE и SURFACE_HI (WCAG AA для мелкого текста).
const TEXT_FAINT: Color = Color("8a847a")
const ACCENT: Color = Color("7cc4ff")
const ACCENT_DEEP: Color = Color("2f6fb8")
const ACCENT_2: Color = Color("b388ff")
const SUCCESS: Color = Color("4ade80")
const WARNING: Color = Color("f5b83d")
const DANGER: Color = Color("f0445a")
const GOLD: Color = Color("f5c451")
const LIFE: Color = Color("ff5a7a")
const AIR: Color = Color("ffd27d")
const BOSS: Color = Color("ff5577")

const FS_XS: int = 13
const FS_S: int = 14
const FS_M: int = 16
const FS_L: int = 20
const FS_XL: int = 28
const FS_XXL: int = 40
const FS_HERO: int = 84

const SP_1: int = 4
const SP_2: int = 8
const SP_3: int = 12
const SP_4: int = 16
const SP_5: int = 24
const SP_6: int = 32

const R_S: int = 6
const R_M: int = 10
const R_L: int = 16

const T_FAST: float = 0.12
const T_BASE: float = 0.2
const T_SLOW: float = 0.35

## Прозрачность «стекла»: доля цвета панели поверх размытого фона.
const GLASS_TINT: float = 0.9

const FONT_INTER: String = "res://assets/fonts/Inter.ttf"
const FONT_CORMORANT: String = "res://assets/fonts/Cormorant.ttf"
## Заголовки — капитель Cormorant SC (статические начертания): «высеченные» буквы с полной кириллицей.
const FONT_HEADING: String = "res://assets/fonts/CormorantSC-SemiBold.ttf"
const FONT_HEADING_BOLD: String = "res://assets/fonts/CormorantSC-Bold.ttf"
## 9-slice рамки и иконки (SVG → DPITexture: чёткие при любом масштабе UI).
const UI_DIR: String = "res://assets/ui/"

static var _fonts: Dictionary = {}
## Палитра для дальтоников (Okabe–Ito, различима при всех частых видах дальтонизма).
## Форма у каждого гема и типа урона и так своя — палитра лишь усиливает различие.
static var colorblind: bool = false
const CB_GEM: Dictionary = {
	"ruby": "#d55e00", "sapphire": "#3a8fd8", "emerald": "#009e73", "topaz": "#e69f00",
	"amethyst": "#cc79a7", "aquamarine": "#56b4e9", "opal": "#f0e442", "diamond": "#e8e8e8",
}
const CB_DTYPE: Dictionary = {
	"physical": "#e8e8e8", "pierce": "#cc79a7", "siege": "#e69f00", "fire": "#d55e00",
	"frost": "#56b4e9", "nature": "#009e73", "arcane": "#3a8fd8", "pure": "#f0e442",
}
## Значок каждого типа урона (UiIcon): цвет не единственный признак.
const DTYPE_ICON: Dictionary = {
	"physical": "swords", "pierce": "arrow_up", "siege": "target", "fire": "flame",
	"frost": "snowflake", "nature": "leaf", "arcane": "sparkle", "pure": "gem",
}


## Длительность анимации с учётом настройки «Уменьшить анимации».
static func dur(t: float) -> float:
	return 0.0001 if Settings.reduce_motion() else t


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var ts: TextServer = TextServerManager.get_primary_interface()
	var fv: FontVariation = FontVariation.new()
	var weight: int = 500
	match kind:
		"ui":
			fv.base_font = load(FONT_INTER)
			weight = 450
		"ui_medium":
			fv.base_font = load(FONT_INTER)
			weight = 560
		"ui_bold":
			fv.base_font = load(FONT_INTER)
			weight = 680
		"num":
			fv.base_font = load(FONT_INTER)
			weight = 620
			fv.opentype_features = {ts.name_to_tag("tnum"): 1}
		"caps":
			fv.base_font = load(FONT_INTER)
			weight = 640
			fv.spacing_glyph = 2
		"heading":
			fv.base_font = load(FONT_HEADING)
			weight = 600
		"heading_bold":
			fv.base_font = load(FONT_HEADING_BOLD)
			weight = 700
		_:
			fv.base_font = load(FONT_INTER)
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	_fonts[kind] = fv
	return fv


## Цвет уровня сложности в HUD и итогах: от спокойного к тревожному. Неизвестный уровень — обычный текст.
const DIFFICULTY_COLOR: Dictionary = {"easy": SUCCESS, "normal": ACCENT, "hard": WARNING, "extreme": DANGER}


static func difficulty_color(id: String) -> Color:
	return DIFFICULTY_COLOR.get(id, TEXT)


## Цвета гемов в кадре (ART_DIRECTION.md §3.2): подобраны под тёплое светлое поле. В data/gems.json
## цвета не меняются — файл входит в хеш данных (сейвы, реплеи, рекорды, сеть).
const ART_GEM: Dictionary = {
	"ruby": "#e0193f", "sapphire": "#2463eb", "emerald": "#10b567", "topaz": "#f59e0b",
	"amethyst": "#9b4dff", "aquamarine": "#22c7d6", "opal": "#f2b8e6", "diamond": "#eaf6ff",
}
## Сила радужного «огня» по гемам: у алмаза и опала больше всего.
const GEM_DISPERSION: Dictionary = {"diamond": 1.0, "opal": 0.9, "aquamarine": 0.6, "topaz": 0.5}


static func gem_dispersion(gem_id: String) -> float:
	return float(GEM_DISPERSION.get(gem_id, 0.35))


static func gem_color(gem_id: String) -> Color:
	if colorblind and CB_GEM.has(gem_id):
		return Color.html(String(CB_GEM[gem_id]))
	if ART_GEM.has(gem_id):
		return Color.html(String(ART_GEM[gem_id]))
	var g: Dictionary = GameData.load_default().gem(gem_id)
	return Color.html(String(g.get("color", "#ffffff")))


static func dtype_color(dtype: String) -> Color:
	if colorblind and CB_DTYPE.has(dtype):
		return Color.html(String(CB_DTYPE[dtype]))
	return Color.html(String(GameData.load_default().damage_colors.get(dtype, "#ffffff")))


static func quality_color(q: int) -> Color:
	return [Color("aab3c5"), Color("8fd3ff"), Color("b18cff"), Color("ffc65c"), Color("ff7ad9")][clampi(q - 1, 0, 4)]


static func format_number(v: float) -> String:
	var a: float = absf(v)
	if a >= 1_000_000.0:
		return "%.1fM" % (v / 1_000_000.0)
	if a >= 10_000.0:
		return "%.1fK" % (v / 1000.0)
	if a >= 100.0 or is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.1f" % v


## Ключ перевода с формой по числу: base_ONE / base_FEW / base_MANY. Русский — 1, 21 волна; 2–4, 42 волны;
## 5–20, 25 волн. Остальные языки — ONE только для 1 (у них FEW и MANY совпадают).
static func plural_key(base: String, n: int) -> String:
	var a: int = absi(n)
	if TranslationServer.get_locale().begins_with("ru"):
		if a % 10 == 1 and a % 100 != 11:
			return base + "_ONE"
		if a % 10 >= 2 and a % 10 <= 4 and (a % 100 < 12 or a % 100 > 14):
			return base + "_FEW"
		return base + "_MANY"
	return base + ("_ONE" if a == 1 else "_MANY")


## «12/42» или «12/∞» (бесконечная «Гонка», total ≤ 0).
static func wave_fraction(n: int, total: int) -> String:
	return "%d/%d" % [n, total] if total > 0 else "%d/∞" % n


static func format_time(seconds: float) -> String:
	var s: int = int(roundf(seconds))
	return "%d:%02d" % [int(float(s) / 60.0), s % 60]
