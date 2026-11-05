shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Линия маршрута: бегущие шевроны вдоль пути. UV.x — длина, UV.y — поперёк.
// Смешивание, а не сложение: поле светлое, и прибавленный свет на нём не виден.
uniform vec4 color : source_color = vec4(0.12, 0.33, 0.78, 1.0);
uniform float speed = 1.4;
uniform float spacing = 0.9;
uniform float intensity = 0.55;

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float k = fract((UV.x - across * 0.35) / spacing - TIME * speed / spacing);
	float chevron = smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.32, 0.5, k));
	float core = 1.0 - smoothstep(0.55, 1.0, across);
	ALBEDO = color.rgb;
	ALPHA = clamp(intensity * 1.5 * (0.3 * core + chevron * core), 0.0, 1.0);
}
