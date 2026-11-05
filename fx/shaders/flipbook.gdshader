shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;
// Флипбук-billboard (Unity Labs, CC0): дым, пыль, взрыв, пламя. Кадр — по progress [0, 1], соседние кадры
// смешиваются. Premultiplied alpha: opacity = 1 — обычное смешивание (дым), 0 — чистое сложение.
// Поле светлое: чистое сложение огня на нём почти не видно, поэтому у пламени opacity ~0.5 — оно
// частично заслоняет фон и читается цветом, а не только свечением.

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(8.0, 8.0);
uniform float progress = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 1.0;
// 1 — у листа нет альфы (огненный шар на чёрном): альфа берётся из яркости.
uniform float luma_alpha = 0.0;
uniform float intensity = 1.0;
// 1 — основание квадрата внизу (столб дыма, пламя растут от земли), 0 — центр.
uniform float pivot_bottom = 0.0;
// Затухание в конце клипа (доля длительности).
uniform float fade_out = 0.25;

void vertex() {
	VERTEX.y += 0.5 * pivot_bottom;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

vec4 frame(float f, vec2 uv) {
	float col = mod(f, grid.x);
	float row = floor(f / grid.x);
	return texture(sheet, (vec2(col, row) + uv) / grid);
}

void fragment() {
	float frames = grid.x * grid.y;
	float f = clamp(progress, 0.0, 1.0) * (frames - 1.0);
	float f0 = floor(f);
	vec4 c = mix(frame(f0, UV), frame(min(f0 + 1.0, frames - 1.0), UV), f - f0);
	float fade = 1.0 - smoothstep(1.0 - fade_out, 1.0, progress);
	float src_a = mix(c.a, clamp(max(c.r, max(c.g, c.b)) * 1.4, 0.0, 1.0), luma_alpha);
	float a = src_a * tint.a * fade;
	ALBEDO = c.rgb * tint.rgb * intensity * a;
	ALPHA = a * opacity;
}
