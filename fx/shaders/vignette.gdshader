shader_type canvas_item;
// Экранная виньетка и вспышки (потеря жизни, босс). Хроматическая аберрация — только при pulse > 0.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 0.55;
uniform vec4 flash_color : source_color = vec4(1.0, 0.2, 0.3, 1.0);
uniform float flash = 0.0;
uniform float aberration = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r = length(d * vec2(1.25, 1.0));
	vec3 col = texture(screen_tex, uv).rgb;
	if (aberration > 0.0005) {
		col.r = texture(screen_tex, uv + d * aberration).r;
		col.b = texture(screen_tex, uv - d * aberration).b;
	}
	float v = smoothstep(0.35, 0.95, r);
	col *= 1.0 - v * strength;
	col = mix(col, flash_color.rgb, v * flash * 0.6);
	COLOR = vec4(col, 1.0);
}
