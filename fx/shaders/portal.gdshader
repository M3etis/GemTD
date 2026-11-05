shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Диск портала: закрученная спираль энергии (PlaneMesh 2×2 внутри тора).
uniform vec4 color : source_color = vec4(0.49, 0.77, 1.0, 1.0);
uniform float intensity = 1.6;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 3.0 + r * 9.0 - TIME * 3.2);
	float core = 1.0 - smoothstep(0.0, 0.85, r);
	float edge = smoothstep(0.55, 0.95, r) * (1.0 - smoothstep(0.95, 1.0, r));
	float m = step(r, 1.0) * (core * (0.35 + 0.65 * swirl) + edge * 0.6);
	ALBEDO = color.rgb * intensity * m;
}
