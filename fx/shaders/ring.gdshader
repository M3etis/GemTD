shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Круг радиуса атаки/ауры на земле (PlaneMesh 2×2, масштабируется по радиусу).
// Смешивание, а не сложение: поле светлое. Светлые цвета (алмаз, аметист) затемняются, чтобы круг читался.
uniform vec4 color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float thickness = 0.03;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(1.0 - thickness * 2.0, 1.0 - thickness, r) * (1.0 - smoothstep(1.0 - thickness * 0.3, 1.0, r));
	float a = atan(p.y, p.x);
	float ticks = step(0.5, fract(a * 36.0 / 6.2831 - TIME * 0.3)) * ring;
	float fill = step(r, 1.0) * (0.035 + 0.06 * smoothstep(0.6, 1.0, r));
	float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = color.rgb * mix(0.85, 0.5, smoothstep(0.55, 0.9, lum));
	ALPHA = clamp(intensity * (ring * 0.95 + ticks * 0.35 + fill * 1.6), 0.0, 1.0);
}
