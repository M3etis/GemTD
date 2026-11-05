shader_type canvas_item;
// «Стеклянная» панель: размытый фон под панелью + тон цвета панели (StyleBox рисуется непрозрачным).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 6.0) = 3.0;
uniform float tint : hint_range(0.0, 1.0) = 0.78;

void fragment() {
	vec3 bg = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	// Лёгкий вертикальный градиент «блика» сверху.
	float sheen = (1.0 - UV.y) * 0.035;
	COLOR = vec4(mix(bg, COLOR.rgb, tint) + sheen, COLOR.a);
}
