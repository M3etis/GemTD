shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled, depth_draw_always;
// Кристалл с фейковым преломлением (экранная текстура) — пресеты Medium и выше.
#define REFRACT
#include "res://fx/shaders/gem_core.gdshaderinc"
