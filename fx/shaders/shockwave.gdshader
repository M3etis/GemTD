shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Ударная волна с искажением: расходящееся кольцо сдвигает изображение под собой (экранная текстура).
// PlaneMesh 2×2, масштабируется по радиусу; progress 0..1 — радиус волны.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 color : source_color = vec4(1.0);
uniform float progress = 0.0;
uniform float strength = 0.035;
uniform float width = 0.14;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float band = 1.0 - smoothstep(0.0, width, abs(r - progress));
	float fade = (1.0 - progress) * step(r, 1.0);
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0);
	vec3 world_dir = (MODEL_MATRIX * vec4(dir.x, 0.0, dir.y, 0.0)).xyz;
	vec2 view_dir = normalize((VIEW_MATRIX * vec4(world_dir, 0.0)).xy + vec2(0.0001));
	vec2 offset = view_dir * vec2(1.0, -1.0) * band * strength * fade;
	vec3 col = texture(screen_tex, SCREEN_UV - offset).rgb;
	ALBEDO = col + color.rgb * band * fade * 0.35;
	ALPHA = band * fade;
}
