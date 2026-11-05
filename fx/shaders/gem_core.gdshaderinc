// Общее ядро шейдера кристаллов (gem.gdshader / gem_refract.gdshader).
// Огранённый драгоценный камень (ART_DIRECTION.md §6): тёмное прозрачное тело, сквозь которое видно поле
// с дисперсией (REFRACT, пресеты Medium+), резкий контраст соседних граней, светлые кромки граней,
// «сердце» у оси, радужные искры («огонь»), отражения неба HDRI. Плюс пульс, голограмма кандидата и трещины
// цитадели.
uniform vec4 gem_color : source_color = vec4(1.0, 0.25, 0.35, 1.0);
uniform float glow = 1.0;
// Сила радужного «огня» и расщепления цветов в преломлении (алмаз — 1.0).
uniform float dispersion = 0.5;
// Полировка (качество I–V): матовый «осколок» → зеркальный «призматический» камень.
uniform float polish = 1.0;
uniform float pulse = 0.0;
uniform float phase = 0.0;
uniform float hologram = 0.0;
uniform float dim = 1.0;
uniform float cracks = 0.0;
#ifdef REFRACT
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
#endif

varying vec3 v_local;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

// Края ячеек Вороного (F2 − F1): тонкие линии трещин.
float crack_edges(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash3(i + g), hash3(i + g + 17.3), hash3(i + g + 41.7));
				float d = length(g + o - f);
				if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
			}
		}
	}
	return d2 - d1;
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	if (dot(n, VIEW) < 0.0) { n = -n; }
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float facet = hash3(floor(wn * 5.0 + 0.5));
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	float t = TIME * 1.7 + phase;
	float beat = 0.8 + 0.2 * sin(t);
	vec3 c = gem_color.rgb;
	// Свечение глубже исходного цвета: на ярких гранях чистый цвет иначе выцветает в пастель.
	vec3 cd = pow(c, vec3(1.6));
	// Огранка читается по контрасту: соседние грани резко различаются по яркости.
	float bright = smoothstep(0.35, 0.95, facet);
	// Кромки граней: на стыке граней нормаль внутри квадрата 2×2 пикселя скачет.
	float edge = clamp(length(fwidth(wn)) * 2.2, 0.0, 1.0);
	// «Сердце» камня — свечение у оси кристалла.
	float heart = exp(-length(v_local.xz) * 6.0);
	vec3 albedo = c * (0.03 + 0.12 * facet * facet);
#ifdef REFRACT
	// Сквозь камень видно поле, сдвинутое гранями; каналы сдвинуты по-разному — дисперсия.
	vec2 ofs = n.xy * (0.03 + 0.025 * facet);
	float k = 0.15 * dispersion * polish;
	vec3 behind = vec3(
		textureLod(screen_tex, SCREEN_UV - ofs * (1.0 - k), 0.0).r,
		textureLod(screen_tex, SCREEN_UV - ofs, 0.0).g,
		textureLod(screen_tex, SCREEN_UV - ofs * (1.0 + k), 0.0).b);
	albedo = mix(albedo, behind * cd * 1.1, 0.45 * ndv);
#endif
	// Диэлектрик с зеркальной полировкой: отражения дают небо HDRI и свет сцены.
	albedo += c * 0.08 * (1.0 - polish);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.32, 0.03, polish);
	SPECULAR = 1.0;
	vec3 fire = 0.5 + 0.5 * cos(6.2831 * (facet * 3.0 + ndv * 2.0 + vec3(0.0, 0.33, 0.67)));
	float sparkle = pow(facet, 12.0) * (0.5 + 0.5 * sin(t * 3.1 + facet * 31.0));
	// Яркие грани редки (вспышки), остальные — глубокий тёмный цвет; так глаз читает огранённый камень.
	float flash = bright * bright * bright;
	// Рост яркости по качеству сжат (0.8 → 2.8 даёт ×1.0 → ×2.1), иначе «призматический» камень выгорает в пятно.
	float g = pow(glow, 0.6);
	vec3 em = cd * g * (flash * 0.9 * beat + heart * 0.55 * beat + fres * 0.45);
	em += mix(cd, vec3(1.0), 0.45) * edge * g * 0.75 * mix(0.4, 1.0, polish);
	em += mix(vec3(1.0), fire, dispersion) * sparkle * g * 1.1 * polish * polish;
	em += c * pulse * 2.5;
	float scan = 0.5 + 0.5 * sin(TIME * 9.0 + (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y * 28.0);
	em *= 1.0 + hologram * (scan * 0.5 - 0.15);
	if (cracks > 0.001) {
		vec3 cp = v_local * 5.0;
		float e = crack_edges(cp);
		float line = 1.0 - smoothstep(0.0, 0.04 + 0.05 * cracks, e);
		float active = step(hash3(floor(cp)), cracks * 1.2);
		float m = line * active;
		albedo *= 1.0 - m * 0.8;
		em = em * (1.0 - m) + vec3(1.0, 0.45, 0.3) * m * 0.6 * cracks;
	}
	ALBEDO = albedo;
	EMISSION = em * dim;
}
