shader_type canvas_item;
// Переход между экранами: кристаллическая «мозаика» из граней, закрывающая экран.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.027, 0.031, 0.051, 1.0);
uniform vec4 edge_color : source_color = vec4(0.49, 0.77, 1.0, 1.0);
uniform float cells = 18.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 uv = UV * aspect * cells;
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float best = 8.0;
	vec2 best_id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = hash2(cell + o);
			float d = length(o + h - f);
			if (d < best) { best = d; best_id = cell + o; }
		}
	}
	float order = hash2(best_id).x * 0.55 + (UV.x * 0.3 + UV.y * 0.15);
	float t = progress * 1.45 - order * 0.45;
	float a = smoothstep(0.0, 0.08, t);
	float edge = smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(0.04, 0.12, t));
	COLOR = mix(vec4(tint.rgb, a), vec4(edge_color.rgb, a), edge * 0.8);
}
