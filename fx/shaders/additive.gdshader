shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Аддитивный материал для лучей, вспышек, молний и снарядов. Цвет — из вершин/экземпляров.
uniform vec4 tint : source_color = vec4(1.0);
uniform float intensity = 1.0;
uniform float fade_y = 0.0;
varying vec3 v_color;
varying float v_alpha;

void vertex() {
	v_color = COLOR.rgb;
	v_alpha = COLOR.a;
}

void fragment() {
	float f = fade_y > 0.0 ? 1.0 - smoothstep(0.0, 1.0, UV.y) : 1.0;
	ALBEDO = v_color * tint.rgb * intensity * v_alpha * f;
}
