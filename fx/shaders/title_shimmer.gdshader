shader_type canvas_item;
// Блик, пробегающий по заголовку (в экранных координатах, т.к. UV текста — это UV атласа шрифта).
uniform vec4 shine : source_color = vec4(0.75, 0.9, 1.0, 1.0);
uniform float speed = 260.0;
uniform float width = 70.0;
uniform float period = 2600.0;

void fragment() {
	float x = FRAGCOORD.x + FRAGCOORD.y * 0.35;
	float band = mod(x - TIME * speed, period);
	float k = 1.0 - smoothstep(0.0, width, abs(band - width));
	COLOR.rgb = mix(COLOR.rgb, shine.rgb, k * 0.65 * COLOR.a);
}
