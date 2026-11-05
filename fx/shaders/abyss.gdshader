shader_type spatial;
render_mode unshaded;
// Бездна под ареной: глубокий градиент от индиго-дымки у края поля к чернильной темноте вдали.
// Неосвещаемая и спокойная — фон не спорит с полем (ART_DIRECTION.md §3.3); объём дают скалы и туман.
uniform vec4 deep_color : source_color = vec4(0.027, 0.031, 0.051, 1.0);
uniform vec4 haze_color : source_color = vec4(0.086, 0.102, 0.227, 1.0);
uniform vec2 arena_half = vec2(16.5, 12.5);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 q = wp.xz;
	vec2 d = max(abs(q) - arena_half, 0.0);
	float dist = length(d);
	// Медленно дрейфующая дымка: два слоя шума, без резких деталей.
	float n = vnoise(q * 0.07 + TIME * 0.01) * 0.6 + vnoise(q * 0.19 - TIME * 0.015) * 0.4;
	float near = exp(-dist * 0.09);
	ALBEDO = mix(deep_color.rgb, haze_color.rgb, clamp(near * (0.55 + 0.45 * n), 0.0, 1.0));
}
