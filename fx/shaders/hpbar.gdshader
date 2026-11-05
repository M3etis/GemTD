shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;
// Полоска здоровья (MultiMesh, billboard). INSTANCE_CUSTOM = (доля, прозрачность, ширина, стиль: 0 враг, 1 босс, 2 щит).
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	VERTEX.x *= max(v_custom.z, 0.2);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float hp = v_custom.x;
	vec2 uv = UV;
	float inside = step(0.12, uv.y) * step(uv.y, 0.88) * step(0.02, uv.x) * step(uv.x, 0.98);
	float fill_x = (uv.x - 0.02) / 0.96;
	vec3 full = mix(vec3(1.0, 0.3, 0.38), vec3(0.4, 1.0, 0.6), smoothstep(0.15, 0.75, hp));
	full = mix(full, vec3(1.0, 0.35, 0.5), clamp(v_custom.w, 0.0, 1.0));
	full = v_custom.w > 1.5 ? vec3(0.55, 0.92, 1.0) : full;
	vec3 c = fill_x < hp ? full : vec3(0.06, 0.07, 0.1);
	ALBEDO = inside > 0.5 ? c : vec3(0.0);
	ALPHA = v_custom.y * (inside > 0.5 ? 0.95 : 0.7);
}
