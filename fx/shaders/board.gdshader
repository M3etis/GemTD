shader_type spatial;
render_mode specular_schlick_ggx;
// Пол арены: известняковые плиты (ambientCG Tiles139, CC0), одна плита — одна клетка, швы плит — границы клеток.
// В текстуре 6×6 разных плит: каждая клетка берёт случайную плиту и поворот, поэтому узор не повторяется.
// Нарисованная сетка видна только в фазе строительства (grid_visibility), зоны без стройки и клетка под
// курсором тонируют камень.
uniform vec2 board_size = vec2(32.0, 24.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// R — AO (из карты высот), G — roughness, B — высота.
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tiles_per_texture = 6.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Скан пёстрый и тёплый: насыщенность и разброс тона между плитами приглушаются к среднему камню.
uniform float saturation = 0.45;
uniform float tone_spread = 0.6;
uniform float tone_mean = 0.62;
uniform float normal_depth = 1.0;
uniform vec4 line_color : source_color = vec4(0.42, 0.38, 0.32, 1.0);
uniform vec4 zone_color : source_color = vec4(0.62, 0.76, 0.95, 1.0);
uniform sampler2D zone_tex : filter_nearest;
uniform vec2 hover_cell = vec2(-100.0, -100.0);
uniform vec4 hover_color : source_color = vec4(0.5, 0.85, 1.0, 1.0);
uniform float grid_strength = 0.3;
// 1 — фаза строительства (сетка видна), 0 — бой.
uniform float grid_visibility = 1.0;
uniform float self_light = 0.03;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 g = UV * board_size;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	// Случайная плита из атласа 6×6 и поворот на 0/90/180/270°. Производные берутся от непрерывных
	// координат (с тем же поворотом), иначе на границах клеток выбирается не тот мип-уровень.
	float pick = floor(hash(cell) * tiles_per_texture * tiles_per_texture);
	vec2 tile = vec2(mod(pick, tiles_per_texture), floor(pick / tiles_per_texture));
	int rot = int(floor(hash(cell + 17.3) * 4.0));
	mat2 r = rot == 0 ? mat2(vec2(1.0, 0.0), vec2(0.0, 1.0)) : rot == 1 ? mat2(vec2(0.0, 1.0), vec2(-1.0, 0.0))
		: rot == 2 ? mat2(vec2(-1.0, 0.0), vec2(0.0, -1.0)) : mat2(vec2(0.0, -1.0), vec2(1.0, 0.0));
	vec2 local = r * (f - 0.5) + 0.5;
	vec2 tuv = (tile + local) / tiles_per_texture;
	vec2 dx = r * dFdx(g) / tiles_per_texture;
	vec2 dy = r * dFdy(g) / tiles_per_texture;
	vec3 alb = textureGrad(albedo_tex, tuv, dx, dy).rgb;
	float l = dot(alb, vec3(0.299, 0.587, 0.114));
	alb = mix(vec3(l), alb, saturation);
	alb = (vec3(tone_mean) + (alb - vec3(tone_mean)) * tone_spread) * tint.rgb;
	vec3 orm = textureGrad(orm_tex, tuv, dx, dy).rgb;
	vec3 nt = textureGrad(normal_tex, tuv, dx, dy).rgb * 2.0 - 1.0;
	// Нормаль в пространстве текстуры повёрнута вместе с плитой — возвращаем её в пространство клетки.
	nt.xy = transpose(r) * nt.xy;
	vec2 e2 = min(f, 1.0 - f);
	float edge = min(e2.x, e2.y);
	float line = 1.0 - smoothstep(0.0, 0.02, edge);
	vec3 col = mix(alb, line_color.rgb, line * grid_strength * grid_visibility);
	float zone = texture(zone_tex, (cell + 0.5) / board_size).r;
	col = mix(col, zone_color.rgb * (0.8 + 0.2 * orm.r), zone * 0.45);
	float hv = step(abs(cell.x - hover_cell.x), 0.1) * step(abs(cell.y - hover_cell.y), 0.1);
	float hv_edge = 1.0 - smoothstep(0.0, 0.1, edge);
	col = mix(col, hover_color.rgb, hv * (0.35 + 0.5 * hv_edge));
	ALBEDO = col;
	NORMAL_MAP = nt * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = orm.g;
	METALLIC = 0.0;
	SPECULAR = 0.4;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.35;
	EMISSION = col * self_light + hover_color.rgb * hv * hv_edge * 0.35;
}
