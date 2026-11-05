shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
// Руны статусов над врагом (MultiMesh, billboard). INSTANCE_CUSTOM.r — тип:
// 0 яд (капля), 1 замедление (снежинка), 2 оглушение (кольцо вращающихся рун), 3 снижение брони (треснувший щит), 4 метка (прицел).
varying float v_kind;

void vertex() {
	v_kind = INSTANCE_CUSTOM.r;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w * 0.6, w, length(pa - ba * h));
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * vec2(1.0, -1.0);
	float r = length(p);
	int kind = int(v_kind + 0.5);
	float m = 0.0;
	vec3 col = vec3(1.0);
	if (kind == 0) {
		// Капля: круг снизу + сужение вверх.
		vec2 q = p - vec2(0.0, -0.2);
		float drop = 1.0 - smoothstep(0.42, 0.5, length(q));
		float tip = step(-0.1, p.y) * (1.0 - smoothstep(0.0, 0.06, abs(p.x) - (0.75 - p.y) * 0.45));
		m = max(drop, tip * step(p.y, 0.72));
		col = vec3(0.35, 1.0, 0.45);
	} else if (kind == 1) {
		for (int i = 0; i < 3; i++) {
			float a = float(i) * 1.0472;
			vec2 d = vec2(cos(a), sin(a)) * 0.75;
			m = max(m, seg(p, -d, d, 0.12));
		}
		col = vec3(0.55, 0.85, 1.0);
	} else if (kind == 2) {
		float a = atan(p.y, p.x) + TIME * 3.0;
		float ring = 1.0 - smoothstep(0.08, 0.14, abs(r - 0.62));
		float runes = step(0.55, fract(a * 6.0 / 6.2831)) * ring;
		m = max(runes, (1.0 - smoothstep(0.1, 0.2, r)) * 0.8);
		col = vec3(1.0, 0.9, 0.45);
	} else if (kind == 3) {
		float shield = (1.0 - smoothstep(0.0, 0.08, max(abs(p.x) - 0.55 + max(0.0, -p.y) * 0.55, abs(p.y) - 0.7)));
		float crack = seg(p, vec2(-0.15, 0.7), vec2(0.1, 0.0), 0.12) + seg(p, vec2(0.1, 0.0), vec2(-0.1, -0.6), 0.12);
		m = clamp(shield - crack, 0.0, 1.0);
		col = vec3(1.0, 0.6, 0.25);
	} else {
		float ring = 1.0 - smoothstep(0.08, 0.14, abs(r - 0.6));
		float cross = max(seg(p, vec2(-0.9, 0.0), vec2(-0.35, 0.0), 0.1), seg(p, vec2(0.35, 0.0), vec2(0.9, 0.0), 0.1));
		cross = max(cross, max(seg(p, vec2(0.0, -0.9), vec2(0.0, -0.35), 0.1), seg(p, vec2(0.0, 0.35), vec2(0.0, 0.9), 0.1)));
		m = max(ring, cross);
		col = vec3(1.0, 0.35, 0.4);
	}
	// Тёмная круглая подложка — глиф читается на любом фоне и на светлых врагах.
	float disc = 1.0 - smoothstep(0.92, 1.0, r);
	float rim = (1.0 - smoothstep(0.0, 0.08, abs(r - 0.93))) * 0.8;
	vec3 bg = vec3(0.04, 0.05, 0.09);
	vec3 rgb = mix(bg, col * 1.4, clamp(m, 0.0, 1.0));
	rgb = mix(rgb, col * 0.8, rim * (1.0 - m));
	ALBEDO = rgb;
	ALPHA = max(disc * 0.8, m);
}
