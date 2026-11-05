shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled;
// Мягкое пятно тени под летающим врагом (работает и без теневых карт на Low).
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = (1.0 - smoothstep(0.25, 1.0, length(p))) * 0.6;
	ALBEDO = vec3(1.0 - a);
}
