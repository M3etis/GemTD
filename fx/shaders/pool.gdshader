shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Ядовитая лужа: мерцающий диск с пузырями (PlaneMesh 2×2, масштаб = радиус). Смешивание — поле светлое.
uniform vec4 color : source_color = vec4(0.35, 1.0, 0.5, 1.0);
uniform float intensity = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = smoothstep(1.0, 0.75, r);
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 5.0 + r * 9.0 - TIME * 2.0 + seed);
	vec2 cell = floor(p * 5.0 + seed);
	float bub = step(0.86, hash(cell + floor(TIME * 2.0))) * smoothstep(0.35, 0.0, length(fract(p * 5.0 + seed) - 0.5));
	ALBEDO = color.rgb * (0.7 + 0.3 * swirl) + vec3(bub * 0.3);
	ALPHA = clamp(intensity * edge * (0.32 + 0.22 * swirl + bub * 0.6), 0.0, 1.0);
}
