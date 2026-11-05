shader_type spatial;
render_mode specular_schlick_ggx;
// Враги с запечённой анимацией (tools/bake_enemy_vat.gd): позы по кадрам в VAT, PBR-атлас материалов.
// INSTANCE_CUSTOM = (вспышка попадания, dissolve, статусы: +1 замедление, +2 яд, фаза клипа):
//   фаза [0, 1) — цикл ходьбы или полёта, [1, 2] — клип смерти (если он есть).
// COLOR — цвет архетипа (цвет экземпляра MultiMesh), альфа — «призрачность» под Покровом.

uniform sampler2D vat_pos : filter_nearest, repeat_disable;
uniform sampler2D vat_nrm : filter_nearest, repeat_disable;
// Строк VAT на кадр (вершины свыше ширины текстуры переносятся), кадров цикла и смерти.
uniform int rows = 1;
uniform int loop_frames = 24;
uniform int death_frames = 0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform float emission_energy = 0.0;
// 1 — эмиссия атласа — маска, окрашенная цветом архетипа (прожилки кристаллов).
uniform float emission_tint = 0.0;
// Доля цвета архетипа в альбедо (по яркости текстуры) и сила цветного ободка: на светлом поле
// враг читается силуэтом, а цвет подсказывает тип, как на иконках волн.
uniform float tint = 0.3;
uniform float rim = 0.45;
uniform float albedo_gain = 1.0;

varying vec4 v_custom;
varying vec3 v_color;
varying float v_ghost;
varying vec3 v_local;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

vec3 oct_decode(vec2 e) {
	vec3 v = vec3(e.x, 1.0 - abs(e.x) - abs(e.y), e.y);
	if (v.y < 0.0) {
		v.xz = (1.0 - abs(v.zx)) * vec2(e.x >= 0.0 ? 1.0 : -1.0, e.y >= 0.0 ? 1.0 : -1.0);
	}
	return normalize(v);
}

ivec2 vat_xy(vec2 addr, int frame) {
	return ivec2(int(addr.x), frame * rows + int(addr.y));
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR.rgb;
	v_ghost = 1.0 - COLOR.a;
	float ph = INSTANCE_CUSTOM.w;
	int f0;
	int f1;
	float fr;
	if (ph >= 1.0 && death_frames > 0) {
		float p = clamp(ph - 1.0, 0.0, 1.0) * float(death_frames - 1);
		f0 = int(floor(p));
		f1 = min(f0 + 1, death_frames - 1);
		fr = p - float(f0);
		f0 += loop_frames;
		f1 += loop_frames;
	} else {
		float p = fract(ph) * float(loop_frames);
		f0 = int(floor(p)) % loop_frames;
		f1 = (f0 + 1) % loop_frames;
		fr = fract(p);
	}
	vec3 p0 = texelFetch(vat_pos, vat_xy(UV2, f0), 0).xyz;
	vec3 p1 = texelFetch(vat_pos, vat_xy(UV2, f1), 0).xyz;
	vec4 n0 = texelFetch(vat_nrm, vat_xy(UV2, f0), 0);
	vec4 n1 = texelFetch(vat_nrm, vat_xy(UV2, f1), 0);
	// Знак бинормали берётся из исходных данных меша — соглашение движка не важно.
	float bsign = dot(BINORMAL, cross(NORMAL, TANGENT)) < 0.0 ? -1.0 : 1.0;
	VERTEX = mix(p0, p1, fr);
	NORMAL = normalize(mix(oct_decode(n0.xy), oct_decode(n1.xy), fr));
	vec3 t = normalize(mix(oct_decode(n0.zw), oct_decode(n1.zw), fr));
	TANGENT = normalize(t - NORMAL * dot(NORMAL, t));
	BINORMAL = cross(NORMAL, TANGENT) * bsign;
	v_local = VERTEX;
}

void fragment() {
	float dissolve = v_custom.y;
	// Покров: упорядоченный дизеринг вместо прозрачности (без сортировки), плюс мерцающий контур.
	if (v_ghost > 0.01) {
		vec2 fc = floor(FRAGCOORD.xy);
		float bayer = fract((fc.x * 0.5 + fc.y * 0.25) + fract(fc.x * 0.25 + fc.y * 0.5) * 0.5);
		if (bayer < v_ghost) { discard; }
	}
	float dn = hash3(floor(v_local * 9.0));
	if (dissolve > 0.001 && dn < dissolve) { discard; }
	float burn = dissolve > 0.001 ? 1.0 - smoothstep(0.0, 0.12, dn - dissolve) : 0.0;
	float poison = step(1.5, v_custom.z);
	float slow = step(0.5, v_custom.z - 2.0 * poison);
	vec3 alb = texture(albedo_tex, UV).rgb * albedo_gain;
	vec3 orm = texture(orm_tex, UV).rgb;
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	vec3 col = clamp(mix(vec3(dot(v_color, vec3(0.299, 0.587, 0.114))), v_color, 1.3), 0.0, 1.0);
	alb = mix(alb, col * lum * 1.6, tint);
	alb = mix(alb, vec3(0.55, 0.8, 1.0) * (lum + 0.15), slow * 0.45);
	alb = mix(alb, vec3(0.35, 0.85, 0.4) * (lum + 0.1), poison * 0.3);
	ALBEDO = alb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = texture(emission_tex, UV).rgb * mix(vec3(1.0), col, emission_tint) * emission_energy + col * fres * rim
		+ vec3(1.0) * v_custom.x * 1.2 + vec3(1.0, 0.55, 0.25) * burn * 3.0
		+ vec3(0.4, 0.8, 1.0) * slow * fres * 1.4 + vec3(0.3, 1.0, 0.45) * poison * fres * 0.9
		+ vec3(0.75, 0.65, 1.0) * v_ghost * fres * 2.0;
}
