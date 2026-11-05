shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// След снаряда: вытянутая полоса за снарядом, яркая у головы и гаснущая к хвосту. UV.y = 0 у головы.
varying vec3 v_color;

void vertex() {
	v_color = COLOR.rgb;
}

void fragment() {
	float along = 1.0 - UV.y;
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float m = pow(along, 1.6) * smoothstep(0.0, 0.8, across);
	ALBEDO = v_color * m * 2.2;
}
