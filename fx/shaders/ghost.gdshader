shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
// Призрак камня под курсором: полупрозрачный цвет «можно / нельзя» с ободком (на светлом поле
// аддитивный призрак не виден).
uniform vec4 tint : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float intensity = 0.35;

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint.rgb * 0.85;
	ALPHA = clamp(intensity * 1.3 + rim * 0.45, 0.0, 0.9);
}
