shader_type spatial;
render_mode specular_schlick_ggx;
// Обсидиан: стены лабиринта, цоколи пьедесталов, платформы чекпоинтов, рамка поля.
// Материал — ambientCG Rock035 (CC0) в трипланарной проекции (у процедурных мешей нет UV),
// затемнённый и отполированный до обсидиана. Светлые прожилки (маска в ORM.b) тлеют цветом vein_color;
// vein_pulse поднимает их на мгновение (смена пути, новая стена).
// На блоке стены (скан Poly Haven moon_rock_02) поверх идёт его собственная карта нормалей по UV.
uniform vec4 base_color : source_color = vec4(0.085, 0.078, 0.11, 1.0);
uniform vec4 vein_color : source_color = vec4(0.43, 0.36, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// R — AO, G — roughness, B — маска прожилок.
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.9;
uniform float normal_strength = 0.8;
uniform bool use_uv_detail = false;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D detail_orm : hint_default_white, filter_linear_mipmap_anisotropic;
uniform float vein_energy = 0.35;
uniform float vein_pulse = 0.0;
// Верхние грани чуть светлее: сколы ловят ключевой свет.
uniform float top_sheen = 0.04;

vec3 triplanar_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 bw = triplanar_w(wn);
	vec2 ux = wp.zy * tex_scale;
	vec2 uy = wp.xz * tex_scale;
	vec2 uz = wp.xy * tex_scale;
	vec3 alb = texture(albedo_tex, ux).rgb * bw.x + texture(albedo_tex, uy).rgb * bw.y + texture(albedo_tex, uz).rgb * bw.z;
	vec3 orm = texture(orm_tex, ux).rgb * bw.x + texture(orm_tex, uy).rgb * bw.y + texture(orm_tex, uz).rgb * bw.z;
	// Трипланарные нормали — смешивание «whiteout» (Ben Golus): нормаль каждой проекции в мировые оси.
	vec3 tx = texture(normal_tex, ux).xyz * 2.0 - 1.0;
	vec3 ty = texture(normal_tex, uy).xyz * 2.0 - 1.0;
	vec3 tz = texture(normal_tex, uz).xyz * 2.0 - 1.0;
	tx.xy *= normal_strength;
	ty.xy *= normal_strength;
	tz.xy *= normal_strength;
	tx = vec3(tx.xy + wn.zy, abs(tx.z) * wn.x);
	ty = vec3(ty.xy + wn.xz, abs(ty.z) * wn.y);
	tz = vec3(tz.xy + wn.xy, abs(tz.z) * wn.z);
	vec3 n = normalize(tx.zyx * bw.x + ty.xzy * bw.y + tz.xyz * bw.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float ao = orm.r;
	float rough = mix(0.08, 0.45, orm.g);
	if (use_uv_detail) {
		NORMAL_MAP = texture(detail_normal, UV).xyz;
		vec3 d = texture(detail_orm, UV).rgb;
		ao *= d.r;
		rough = mix(rough, 0.5, smoothstep(0.75, 1.0, d.g) * 0.4);
	}
	// Обсидиан: альбедо камня переводится в почти чёрное стекло с лёгким сине-фиолетовым отливом.
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	float top = smoothstep(0.6, 0.95, wn.y);
	ALBEDO = base_color.rgb * (0.55 + 1.6 * lum) + vec3(top_sheen) * top;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	float glow = vein_energy * (0.8 + 0.2 * sin(TIME * 0.7 + wp.x * 0.5 + wp.z * 0.3)) + vein_pulse * 2.5;
	EMISSION = vein_color.rgb * orm.b * glow;
}
