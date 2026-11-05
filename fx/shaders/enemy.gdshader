shader_type spatial;
render_mode specular_schlick_ggx;
// Враги (MultiMesh): INSTANCE_CUSTOM = (вспышка попадания, dissolve, статусы: +1 замедление, +2 яд, —).
varying vec4 v_custom;
varying vec3 v_color;
varying float v_ghost;
// Осветление детали модели (белки глаз, брюхо) — UV2.x запечённых моделей; у процедурных мешей 0.
varying float v_lift;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR.rgb;
	v_ghost = 1.0 - COLOR.a;
	v_lift = UV2.x;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) { n = -n; }
	NORMAL = n;
	vec3 lp = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dn = hash3(floor(lp * 9.0));
	float dissolve = v_custom.y;
	// Покров: упорядоченный дизеринг вместо прозрачности (без сортировки), плюс мерцающий контур.
	if (v_ghost > 0.01) {
		vec2 fc = floor(FRAGCOORD.xy);
		float bayer = fract((fc.x * 0.5 + fc.y * 0.25) + fract(fc.x * 0.25 + fc.y * 0.5) * 0.5);
		if (bayer < v_ghost) { discard; }
	}
	if (dissolve > 0.001 && dn < dissolve) { discard; }
	float burn = dissolve > 0.001 ? 1.0 - smoothstep(0.0, 0.12, dn - dissolve) : 0.0;
	float poison = step(1.5, v_custom.z);
	float slow = step(0.5, v_custom.z - 2.0 * poison);
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.5);
	// Поле светлое: цвет архетипа (пастельный) насыщается и темнеет, ободок — цветной, а не белёсый.
	vec3 base = clamp(mix(vec3(dot(v_color, vec3(0.299, 0.587, 0.114))), v_color, 1.45), 0.0, 1.0);
	base = mix(base, vec3(0.95), v_lift);
	ALBEDO = base * 0.42 + vec3(0.25, 0.65, 1.0) * slow * 0.35 + vec3(0.2, 0.9, 0.35) * poison * 0.25;
	ROUGHNESS = 0.4;
	METALLIC = 0.15;
	EMISSION = base * fres * 0.6 + vec3(1.0) * v_custom.x * 1.8 + vec3(1.0, 0.55, 0.25) * burn * 3.0
		+ vec3(0.4, 0.8, 1.0) * slow * fres * 1.4 + vec3(0.3, 1.0, 0.45) * poison * fres * 0.9
		+ vec3(0.75, 0.65, 1.0) * v_ghost * fres * 2.0;
}
