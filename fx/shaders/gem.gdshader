shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;
// Кристалл без преломления (пресет Low; кристаллы отбрасывают тень).
#include "res://fx/shaders/gem_core.gdshaderinc"
