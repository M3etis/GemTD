# Кандидаты в ассеты — визуальный ремейк Gem Tower Defense

Дата проверки: 2026-11-03. Статус: **исторический документ** — список кандидатов на момент выбора. Что в итоге стоит в игре — [CREDITS.md](CREDITS.md) и [assets/LICENSES.md](assets/LICENSES.md); замены Fab — в конце файла.
Требования — [ASSET_REQUIREMENTS.md](ASSET_REQUIREMENTS.md), стиль — [ART_DIRECTION.md](ART_DIRECTION.md).

## Как проверяли
- Каждую запись сверяли со страницей источника: API Poly Haven (`/info`, `/files`), API ambientCG, публичный API Sketchfab и вьюер со списком клипов, карточки Fab (через браузер), kenney.nl, game-icons.net, lucide.dev, метаданные google/fonts.
- Что не удалось подтвердить, помечено **«не проверено»**. Полигонаж Sketchfab — `faceCount`, то есть треугольники.
- **Лицензии площадок (проверено):**
  - **Poly Haven** — всё CC0, указывать авторство не нужно (https://polyhaven.com/license).
  - **ambientCG** — всё CC0 1.0 (https://docs.ambientcg.com/license/).
  - **Fab Standard License** (https://www.fab.com/eula, ред. 01.10.2024):
    - коммерческое использование и модификация разрешены;
    - можно использовать в любом движке, не только в Unreal;
    - атрибуция не нужна;
    - запрещено распространять ассет отдельно и давать игрокам его извлекать;
    - хранить в приватном репозитории с соавторами можно;
    - **§6(a): нельзя совмещать с GPL и CC-BY-SA.**
  - **Sketchfab CC BY 4.0** — коммерция разрешена, атрибуция обязательна.

**Состав списка:** 25 основных кандидатов, 6 резервных и 10 отказов. В каждой записи 14 полей из брифа: 1 название, 2 автор, 3 источник и ссылка, 4 лицензия, 5 коммерция, 6 атрибуция, 7 ограничения, 8 формат, 9 текстуры, 10 PBR, 11 полигонаж, 12 LOD / коллизии / риг / анимации, 13 стиль, 14 причина.

> C7 Golem и C9 DemonLord2 (Fab) в итоге из проекта убраны — см. «Замены ассетов Fab» в конце файла.

---

## E. Окружение

### E1. Tiles 139 — пол арены ★ рекомендую
1. Tiles 139 (`Tiles139`)
2. ambientCG
3. ambientCG — https://ambientcg.com/view?id=Tiles139
4. CC0 1.0
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет
8. ZIP с картами JPG или PNG
9. 1K / 2K / 4K / 8K (2K-PNG ≈57 МБ)
10. PBR: color, normal, roughness, displacement. **AO нет.** Тип normal (GL или DX) внутри архива не проверен
11. Полигонаж: —
12. LOD / коллизии / риг / анимации: —
13. Стиль 4.5/5:
    - палитра по API `D7CBB7` / `E2D7C9`, почти точно наш `#D8D0BF`;
    - швы `6D5B47` темнее целевого `#A89F8C`, это правится тонировкой;
    - теги: cream, limestone, worn; образец ≈2×2 м.
14. Лучшее совпадение по цвету, а квадратные плиты подгоняются под клетки. AO запечём из displacement, плюс SSAO.

### E2. Travertine 009 — пол арены (альтернатива)
1. Travertine 009 (`Travertine009`)
2. ambientCG
3. ambientCG — https://ambientcg.com/view?id=Travertine009
4. CC0 1.0
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет
8. ZIP с картами JPG или PNG
9. 1K / 2K / 4K / 8K
10. PBR: color, normal, roughness, displacement, AO (тип normal не проверен)
11. Полигонаж: —
12. LOD / коллизии / риг / анимации: —
13. Стиль 4/5: тон `dcd3bf`, полированный травертин без швов, образец 1.2×1.2 м.
14. Сплошной камень без швов: плиты 4×4 и швы клеток рисуем шейдером ровно по сетке. Это максимум контроля. Блеск нужно снизить через roughness.

### E3. Rock 035 — материал стен ★
1. Rock 035 (`Rock035`)
2. ambientCG
3. ambientCG — https://ambientcg.com/view?id=Rock035
4. CC0 1.0
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет
8. ZIP с картами JPG или PNG
9. 1K / 2K / 4K / 8K (2K-PNG ≈68 МБ)
10. PBR: color, normal, roughness, displacement, AO
11. Полигонаж: —
12. LOD / коллизии / риг / анимации: —
13. Стиль 4/5: палитра `151a1e` / `283338` / `4c5a62`, холодный сине-чёрный, близко к `#15131C`. Есть слабые зеленоватые вкрапления.
14. Готового CC0 obsidian или basalt нет ни на Poly Haven, ни на ambientCG: поиск по API дал 0 результатов. Это самый близкий тон. Глянец обсидиана и жилы `#6E5BFF` делаем в шейдере, зелень сдвигаем по оттенку.

### E4. Moon Rock 02 — меш блока стены ★ (после упрощения)
1. Moon Rock 02 (`moon_rock_02`)
2. Rico Cilliers и Greg Zaal (фото), Jenelle van Heerden (обработка)
3. Poly Haven — https://polyhaven.com/a/moon_rock_02
4. CC0 (открыт 19.06.2025)
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет
8. glTF (`.gltf` + `.bin` + JPG), FBX, Blend, USD; карты PNG / JPG / EXR
9. 1K–8K
10. PBR: Diffuse, nor_gl, nor_dx, Rough, AO, Displacement, ARM
11. Полигонаж: 6 194 треугольника
12. LOD: флаг `lods: true`, уровни не проверены. Коллизий, рига и анимаций нет
13. Стиль 3.5/5: компактная, почти кубическая фотоскан-глыба ≈0.25×0.25×0.2 м, при масштабе ×4 занимает клетку. Альбедо светлое (реголит), его заменяем материалом E3.
14. Единственный близкий CC0-«блок».

    ⚠️ Стен до 1200 штук: 1200 × 6.2K ≈ 7.4M треугольников. **Обязательно упростить до ≈600 треугольников** с запечённой нормалью. Сделать 3–4 варианта поворотом и масштабом.

### E5. Boulder 01 — парящие острова бездны
1. Boulder 01 (`boulder_01`)
2. Rico Cilliers
3. Poly Haven — https://polyhaven.com/a/boulder_01
4. CC0
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет
8. glTF, FBX, Blend, USD
9. 1K–8K
10. PBR: Diffuse, nor_gl, nor_dx, ARM, AO, Rough (displacement нет)
11. Полигонаж: 123 976 треугольников
12. LOD: флаг есть, уровни не проверены. Коллизий, рига и анимаций нет
13. Стиль 3.5/5: ≈1.27×1.83×1.0 м, «рваные грани, лишайник, ржавые потёки». Нужна тёмная тонировка и удаление лишайника. Превью на странице не загрузилось, оценка по описанию.
14. Закрытая глыба — отличный «остров» при масштабе ×5–10. LOD0 тяжёлый: нужны LOD Godot или децимация. На сцене таких 6–10 штук.

### E6. Rock Face 01 — скальные массы бездны
1. Rock Face 01 (`rock_face_01`)
2. Dario Barresi
3. Poly Haven — https://polyhaven.com/a/rock_face_01
4. CC0
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет
8. glTF, FBX, Blend, USD
9. 1K–8K
10. PBR: Diffuse, nor_gl, nor_dx, ARM, AO, Rough
11. Полигонаж: 20 174 треугольника
12. Флага LOD нет. Коллизий, рига и анимаций нет
13. Стиль 3.5/5: 7.1×5.6×5.0 м, слоистая порода с сине-красными минеральными тонами.
14. Очень лёгкий для своих размеров, подходит для массовых инстансов. Обратная сторона, вероятно, открыта (не проверено), но камера под 57° её не видит.

### E7. Kloppenheim 07 (Pure Sky) — HDRI арены ★
1. Kloppenheim 07 (Pure Sky) (`kloppenheim_07_puresky`)
2. Greg Zaal (оригинал), Jarod Guest (небо)
3. Poly Haven — https://polyhaven.com/a/kloppenheim_07_puresky
4. CC0
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет
8. HDR, EXR
9. 1K–24K (4K: HDR 19.4 МБ)
10. PBR: —
11. Полигонаж: —
12. LOD / коллизии / риг / анимации: —
13. Стиль 4.5/5: ночное облачное небо низкого контраста, мягкий лунный свет, холодный ambient, слабое тёплое свечение у горизонта. EV 22.
14. Мягкий холодный ambient без земли на горизонте — то, что нужно бездне. Тёплый горизонт рифмуется с латунью.

### E8. Qwantani Night (Pure Sky) — HDRI меню
1. Qwantani Night (Pure Sky) (`qwantani_night_puresky`)
2. Greg Zaal (фото), Jarod Guest (обработка)
3. Poly Haven — https://polyhaven.com/a/qwantani_night_puresky
4. CC0
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет
8. HDR, EXR
9. 1K–24K (4K: HDR 21.2 МБ)
10. PBR: —
11. Полигонаж: —
12. LOD / коллизии / риг / анимации: —
13. Стиль 4/5: ясная ночь, Млечный Путь, холодное свечение. EV 23.
14. Звёзды в отражениях гемов на крупных планах меню. Риск: в глянцевом обсидиане звёзды могут мерцать.

### E9. Antique Classical Pedestal Stands Type C — пьедестал гемов
1. Antique Classical Pedestal Stands Type C
2. Mad_Lobster_Workshop
3. Sketchfab — https://sketchfab.com/3d-models/antique-classical-pedestal-stands-type-c-9e4d070d27f944ef93e28287ab893ab0
4. **CC BY 4.0**
5. Коммерция: да
6. Атрибуция **нужна**, строка в [CREDITS.md](CREDITS.md)
7. Ограничения: только атрибуция
8. `.blend` и автоконверт Sketchfab glTF / GLB / USDZ; архив 221 МБ
9. 4096×4096 PNG
10. PBR metalness, 8 текстур на 2 материала (состав не проверен)
11. Полигонаж: 31.6K треугольников
12. LOD не заявлены, рига нет, анимаций 0
13. Стиль 4/5: классический постамент с ионической капителью и чашей — готовое место для самоцвета. Есть светлый мраморный вариант.
14. Лучший готовый постамент. На поле до 60 штук, поэтому **упростить до ≈3K** и сжать текстуры до 1K. Латунные пояски — материалом.

### E10. Stone Pillar (Quixel Megascans) — чекпоинты, опоры портала
1. Stone Pillar
2. Quixel Megascans
3. Fab — https://www.fab.com/listings/ef9d1118-5f33-4475-87d4-1e663d985b92
4. Fab Standard License, бесплатно
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нельзя распространять ассет отдельно. Приватный репозиторий допустим
8. FBX, glTF, ZBrush; автоконверт GLB / glTF / USDZ
9. Плотность 5805 px/м; точные разрешения по тирам не проверены
10. PBR: Basecolor, Normal, Roughness, Gloss, Specular, AO, Cavity, Bump, Displacement (только high tier). Тип normal не проверен
11. Полигонаж: не проверено (на странице не указан)
12. LOD не проверено; меш открытый (Open mesh); рига и анимаций нет
13. Стиль 3.5/5: круглый серый столб с базой 0.49×0.49×1.22 м, есть лишайник. Тонируем под известняк или обсидиан, лишайник убираем.
14. Фотоскан для пяти чекпоинтов и опор портала.

---

## C. Существа (враги и боссы)

**Подход:** рядовым врагам запекаем анимации в VAT (vertex animation textures), чтобы рисовать до 300 штук через MultiMesh. Боссы — полноценные skinned-модели.

У всех рядовых кандидатов больше 4K треугольников, их **упрощаем до запекания VAT**: ширина VAT-текстуры зависит от числа вершин. Смерть в игре уже сделана как dissolve с осколками, поэтому отсутствие клипа death не критично.

### C1. HighPolyDensity, линейка «Blight» — рядовые ★
- **Закрывает:** Бронированный (Blight Bug), Щитоносец (Pteran), Рой (Blight Drone, уменьшенный).

1. Blight Bug; Vampirical Blight Drone (плюс перекраски Fireborne и Pale); Pteran – Humanoid Beetle
2. HighPolyDensity
3. Sketchfab:
   - https://sketchfab.com/models/eca3cc1f85a64f70ba86cea09963d42c
   - https://sketchfab.com/models/b214751af77b4609be858399923eea41
   - https://sketchfab.com/models/6fe9ab8e42554c83bfc4ae1571007c0d
4. **CC BY 4.0**
5. Коммерция: да
6. Атрибуция **нужна**
7. Ограничения: только атрибуция
8. Автоконверт glTF (исходник не указан, не проверено)
9. Разрешение не указано; 8 / 18 / 35 текстур
10. PBR: да (Drone и Pteran — Quixel Mixer), состав карт не перечислен
11. Полигонаж: 16 370 / 16 370 / 11 502 → упростить до ≤4K
12. Риг: есть. Клипы:
    - Bug: Defensive Idle, Walk Cycle Loop, Heavy и Light Attack, Burrow, Stagger;
    - Drone: Heavy и Light Attack, Burrow, Defensive Idle, Falter, Walk;
    - Pteran: Idle, Defensive Idle, Walk, Limp, Inspect, Headbutt.

    Death нет.
13. Стиль 8/10: реалистично-гротескная органика, один автор, один пайплайн.
14. Единственная бесплатная связная линейка, где есть и рядовые, и боссы (C2). Роль hit играют Stagger и Falter.

### C2. HighPolyDensity, боссы — Матка Роя, Небесный Левиафан ★
1. Vampirical Blight Queen (варианты Fireborne, Ashen, Amethystine, Pale); Stonewisp – Mutant Stingray
2. HighPolyDensity
3. Sketchfab:
   - https://sketchfab.com/models/943c5865b9f94ce48ccea253382c0d77
   - https://sketchfab.com/models/0f65f0ee9ae9425bb6154c4a95a9c62a (Fireborne)
   - https://sketchfab.com/models/ca27ab932b21407ba30376340f4c4444
4. **CC BY 4.0**
5. Коммерция: да
6. Атрибуция **нужна**
7. Ограничения: только атрибуция
8. Автоконверт glTF (не проверено)
9. Разрешение не указано; Queen — 16 текстур и 4 материала, Stonewisp — 27 текстур и 4 материала
10. PBR: Queen — Quixel Mixer; Stonewisp — ZBrush и Substance Painter
11. Полигонаж: 22 976 / 29 310 → упростить до ≤15K
12. Риг: есть. Клипы:
    - Queen: Idle ×3, Walk Cycle, Take Damage, Lay Egg, Shield Block, Leap, Vomit Attack, Burrow, плюс 2 танца. Death нет;
    - Stonewisp: Idle, Swim, Brace (enter, idle, exit), Inspect, Intimidate, **Die**.
13. Стиль 8/10: тёмный реализм. Swim у Stonewisp читается как парение.
14. Lay Egg — готовая анимация призыва Роя у Матки. Та же эстетика, что у C1.

### C3. Ferocious Industries — Быстрый, Ходок, Заговорённый
1. PBR Velociraptor (Animated); PBR Stegasaurus (Animated); PBR Pachycephalasaurus (Animated); PBR Shadowkin Mage (Rigged)
2. Ferocious Industries
3. Sketchfab:
   - https://sketchfab.com/models/8f1744af7b0847a2aabe3df90be802f0
   - https://sketchfab.com/models/ec254ea1554941fe8a131f62db0faf3d
   - https://sketchfab.com/models/6eea5cee4afa4730bf75c6329a43e56d
   - https://sketchfab.com/models/7aab96637055455297d158584b1602cd
4. **CC BY 4.0**
5. Коммерция: да
6. Атрибуция **нужна**
7. Ограничения: только атрибуция
8. Автоконверт glTF (не проверено)
9. Динозавры — 2K (по описанию), Shadowkin — 3–4K
10. PBR:
    - динозавры: Albedo, Normal, AO, плюс «Secondary»; 5 вариантов окраски;
    - Shadowkin: Albedo, Normal, Metallic, AO, Roughness.
11. Полигонаж: Raptor 15 098, Stego 19 839, Pachy 26 112, Shadowkin 16 026 → упростить
12. Риг и клипы:
    - Raptor (26 клипов): Walk, Jog, Sprint, Hurt ×2, Death ×2, Idle, Roar, Bite, Leap и др.;
    - Stego: Walk, Run, HurtA и HurtB, Death, KnockedDown, Idle и др.;
    - Pachy: 21 клип, имена не сняты;
    - Shadowkin: только T-pose и action pose, гуманоидный риг — анимации берём с Mixamo.
13. Стиль 7/10: реалистичная чешуя, но это динозавры, а не фэнтези-монстры. Нужна тёмная перекраска и эмиссивные руны.
14. Самые полные наборы клипов для VAT: у Raptor и Stego есть walk, run, hit и death. Закрывает Быстрого (Raptor), Ходока (Pachy или Stego) и Заговорённого (Shadowkin с анимациями Mixamo).

### C4. Wolf Spider (Rigged) — Рой
1. Wolf Spider (Rigged) – Rabidosa rabida
2. Dreaming In Alternation 27
3. Sketchfab — https://sketchfab.com/models/6392e4cfb64d407182fdad2cea9e0abe
4. **CC BY 4.0**
5. Коммерция: да
6. Атрибуция **нужна**
7. Ограничения: только атрибуция
8. Формат не указан
9. Разрешение не указано; 4 текстуры
10. PBR: не указано
11. Полигонаж: 8 458 → для роя упростить до ≤2K
12. Риг: есть. Клипы: walking, walking fast, running, walking backward, повороты. Hit и death нет
13. Стиль 7/10: реалистичный паук.
14. Хорошая локомоция для самого многочисленного врага. Альтернатива Drone из C1.

### C5. Vampire Bat (Animated) — Летающий
1. Vampire Bat (Animated), есть вариант frost bat
2. rubberduck
3. OpenGameArt — https://opengameart.org/content/vampire-bat-animated
4. **CC0**
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет
8. `animated_vampire_bat.zip`, 16.5 МБ (содержимое не указано)
9. Разрешение не указано (использованы CC0-текстуры yughues)
10. PBR: не указано
11. Полигонаж: 7 732 треугольника (автор сам предлагает децимацию)
12. Риг и анимация: есть, имена клипов не указаны. Fly-loop проверим после скачивания
13. Стиль 6/10: скульпт по фото-референсам, 2018 год.
14. Нулевой лицензионный риск. Уровень детализации проверим на месте.

### C6. Troll — Колосс-мишень
1. Troll
2. Timsblends
3. Sketchfab — https://sketchfab.com/models/59e679e0da5c4906935b8841aefe6dc0
4. **CC BY 4.0**
5. Коммерция: да
6. Атрибуция **нужна**. Автор просит сообщить ему название проекта: это просьба, не условие
7. Ограничения: только атрибуция
8. Blender-исходник, формат архива не указан
9. Разрешение не указано; 20 текстур, 6 материалов
10. PBR: metalness (Substance Painter)
11. Полигонаж: 23 066 → упростить до ≤15K
12. Риг: есть. Клипы: Idle, Walking, Run, Attack ×4, HitReact ×2, **Death**, Turn ×2
13. Стиль 7/10. Полный рендер не дождались, видели размытое превью.
14. Полный боевой набор клипов для босса-мишени.

### C7. Armored Stone Golem – Dark Fantasy Boss — Каменный Страж ★ (бесплатно только сегодня)
1. Armored Stone Golem – Dark Fantasy Boss
2. Alexander Lenski
3. Fab — https://www.fab.com/listings/e40713f0-ebea-4f4d-ad9b-b577db4432d5
4. Fab Standard License; **бесплатно до 03.11.2026 19:59**, затем ≈₸31 568 (Personal)
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения:
   - запрещено распространять ассет отдельно;
   - §6(a) — нельзя совмещать с CC-BY-SA;
   - на карточке «Allows usage with AI: No» — запрет на обучение генеративных моделей; к нашей работе не относится.
8. Пакеты UE и Unity плюс отдельные файлы: **FBX** (персонаж и анимации), OBJ, 4K TGA; 782 МБ
9. 4K TGA, 12 материалов, 33 карты
10. PBR: Albedo, Roughness, Metallic, Specular, Gloss, Emissive, AO; 4 цветовых варианта
11. Полигонаж: тело 31 772, оружие 13 932 треугольника → упростить в 2–3 раза, текстуры сжать до 2K
12. Риг: UE5 Epic Skeleton. 25 клипов: attack ×5, walk ×4, jog ×4, idle ×4, gethit ×3, **death ×3**, dodge, turn180
13. Стиль 9/10: прямо dark fantasy / Souls-like.
14. Лучшее попадание в стиль из всех существ. Есть FBX, движок Unreal не нужен.

### C8. Dragon for Boss Monster : PBR — Летающий, Небесный Левиафан
1. Dragon for Boss Monster : PBR
2. Dungeon Mason
3. Fab — https://www.fab.com/listings/6c4bd321-0263-44fe-a3d9-82599eeee12c
4. Fab Standard License, бесплатно
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: как у C7
8. **Только пакет Unreal Engine.** Для Godot нужно установить UE и экспортировать FBX; лицензия это разрешает
9. 2048×2048, 4 цветовых варианта
10. PBR: да, состав не перечислен
11. Полигонаж: Usurper 4 832, Terror Bringer 4 684, Nightmare 4 382, Soul Eater 3 864 треугольника
12. Риг: есть; «до 18 анимаций», имена не указаны (не проверено)
13. Стиль 6/10: у автора тег Lowpoly, это скорее MMO-PBR, чем кинематографичный реализм.
14. Идеальный бюджет полигонов, но слабее по стилю, и нужен Unreal для экспорта.

### C9. DemonLord2 и Whisper (Leks) — Обсидиановый Король, Заговорённый
1. DemonLord2; Whisper
2. Leks
3. Fab:
   - https://www.fab.com/listings/19b9f286-1345-4d78-8066-f115aa27a319
   - https://www.fab.com/listings/bdddda7a-e1c0-41ff-b9ac-329648e68a69
4. Fab Standard License:
   - DemonLord2 — бесплатно в тире **Personal** (выручка или финансирование ≤$100K за 12 мес.), Professional ≈₸10 519;
   - Whisper — бесплатно.
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: как у C7. Для бесплатного DemonLord2 нужно подходить под тир Personal
8. DemonLord2 — UE и Unity; Whisper — **только UE**
9. 4096 (можно уменьшить до 1024)
10. PBR: состав не перечислен; DemonLord2 — 7 материалов и 24 текстуры, Whisper — 1 материал и 4 текстуры
11. Полигонаж: DemonLord2 ≈42K (тело 18 460, броня 19 548, молот 3 924) → упростить в ≈3 раза; Whisper 27 710
12. Риг: UE4 Epic Skeleton. Клипы DemonLord2: Attack ×3, Walking ×4, Run, Idle ×3, Taking damage ×2, Death; у Whisper 16 клипов того же состава
13. Стиль 7/10: на превью золотая броня, нужна перекраска под обсидиан.
14. Единственный бесплатный «король демонов» с полным набором клипов.

---

## G. Гемы (hero)

### G1. Gems (21 different shapes) — огранки для 7 гемов ★
1. Gems (21 different shapes)
2. Vivien Deroche (blue-odym)
3. Sketchfab — https://sketchfab.com/models/1fb35b1aefae4d819dde9de90162602a
4. **CC BY 4.0**
5. Коммерция: да
6. Атрибуция **нужна**
7. Ограничения: только атрибуция
8. Автоконверт glTF (не проверено)
9. Текстур нет, и для шейдера преломления они не нужны
10. PBR: нет, 6 цветовых материалов
11. Полигонаж: 3 024 треугольника на все 21 огранку
12. Статика: риг и анимации не нужны
13. Стиль 8/10: настоящие схемы огранки с плоскими фасетами.
14. Огранки: Asscher, Classic Round, Cushion, Emerald, Marquise, Oval, Pear, Princess, Radiant, Trilliant, Octogon и др.

    Предлагаемое соответствие (силуэты из `data/gems.json` сохраняем по смыслу):

    | Гем | Огранка |
    |---|---|
    | Рубин («игла») | Marquise или Oval |
    | Сапфир | Cushion |
    | Изумруд | Emerald |
    | Топаз | Pear |
    | Аметист | Trilliant |
    | Аквамарин | Octogon или Radiant |
    | Алмаз | Classic Round |

### G2. Gemstone Pack — кабошон для опала
1. Gemstone Pack
2. sofyamakingart
3. Sketchfab — https://sketchfab.com/models/68c4ec3dd23247188884243ad8bb2492
4. **CC BY 4.0**
5. Коммерция: да
6. Атрибуция **нужна**
7. Ограничения: только атрибуция
8. `.blend`. Процедурные материалы Blender при экспорте не сохраняются, но нам нужна только геометрия
9. Текстур нет
10. PBR: нет
11. Полигонаж: Cabochon Round 510, Cabochon Oval 640 (остальные огранки 60–384)
12. Статика
13. Стиль 7/10: огранки проще, чем в G1.
14. Даёт кабошон для опала, которого нет в G1.

---

## V. VFX

### V1. Kenney Particle Pack — искры, свечения, кольца, шлейфы ★
1. Particle Pack v1.0 (сборка для Godot — 1.0.2)
2. Kenney (сборка для Godot — Calinou)
3. https://kenney.nl/assets/particle-pack · https://godotengine.org/asset-library/asset/784 · https://github.com/Calinou/kenney-particle-pack
4. **CC0 1.0**
5. Коммерция: да
6. Атрибуция: не нужна (по желанию — «Kenney (kenney.nl)»)
7. Ограничения: нет. Спрайты статичные и белые, цвет задаётся шейдером
8. PNG, 80 файлов (наличие альфа-канала не проверено)
9. 512×512
10. PBR: —
11. Полигонаж: —
12. По 1 кадру: smoke 10, star 9, spark 7, trace 7, flame 6, magic 5, muzzle 5, circle 5, slash 4, light 3, scorch 3, twirl 3 и др.
13. Стиль 7/10: мягкие нейтральные маски хорошо тонируются под латунь и лёд. Стилизованные `star_`, `symbol_`, `window_` не берём.
14. Закрывает искры попаданий, свечения снарядов, ударные кольца, шлейфы и вспышки. Уже собран под Godot 4.

### V2. Unity Labs «Free VFX image sequences and flipbooks» — дым, огонь, взрывы ★
1. Free VFX image sequences and flipbooks (2016)
2. Thomas Iché, Unity Labs Paris (симуляции в Houdini)
3. https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks (архивы по шаблону `unity3d.com/files/labs/downloads/vfx/assets01/<Имя>/<Имя>-flipbooks.zip`; проверена доступность одного архива — HTTP 200, 4.6 МБ)
4. **CC0** (по тексту поста)
5. Коммерция: да
6. Атрибуция: не нужна
7. Ограничения: нет. Файлы от движка не зависят
8. Flipbook-листы, а также кадры EXR (HDR linear) и TGA
9. Разрешение не проверено
10. PBR: —. Есть варианты «-temperature», по названию — карты температуры для градиентной окраски (не проверено)
11. Полигонаж: —
12. 28 последовательностей: дым (Candle, Wispy ×4, Disc), облака ×4, взрывы ×7, FireBall ×4, Flame ×4, SmallFlame ×3. Число кадров не проверено
13. Стиль 8/10: реалистичные симуляции.
14. Единственный проверенный CC0-источник реалистичных flipbook. Для взрывов Сердца Землетрясения, огня Венца Пепла и дыма при раскрытии гема.

---

## U. UI

### U1. Lucide — иконки HUD и меню ★
1. Lucide Icons (2019 иконок)
2. Lucide Icons and Contributors (форк Feather, Cole Bemis)
3. https://lucide.dev/ · лицензия https://lucide.dev/license
4. **ISC**; иконки, унаследованные от Feather, — MIT
5. Коммерция: да
6. Указывать авторов на экране не нужно. В сборку кладём текст ISC и MIT с копирайтами (`assets/LICENSES.md`, экран «Лицензии»)
7. Ограничения: только сохранение уведомлений
8. SVG с обводкой
9. Вектор, сетка 24 px, обводка 2 px (настраивается, планируем 1.5)
10. PBR: —
11. Полигонаж: —
12. LOD / коллизии / риг / анимации: —
13. Стиль 8/10: единая толщина линии рифмуется с латунными линиями ink-glass. Фэнтезийности средне.
14. Все 28 нужных понятий в **одном** визуальном языке:
    - проверены: swords, footprints, skull, crown, gem, clover, bug, fast-forward, coins, snowflake, feather, leaf, crosshair, gauge, pause, play, settings, trophy, x, shield, zap, info, flame, rotate-ccw, upload, download, copy, heart, sparkles;
    - не проверены: volume-2, circle-arrow-up.

    Векторная иконка в `_draw()` масштабируется вместе с UI 80–150 %.

### U2. Шрифты: Cormorant SC + Inter ★
1. Cormorant SC (300–700) для заголовков (семейство Cormorant: SC, Garamond, Unicase) и Inter (variable: opsz 14–32, wght 100–900) для интерфейса
2. Christian Thalmann; Rasmus Andersson
3. https://fonts.google.com/specimen/Cormorant+SC · https://github.com/google/fonts/tree/main/ofl/cormorantsc · https://fonts.google.com/specimen/Inter · https://github.com/rsms/inter
4. **SIL OFL 1.1**, без Reserved Font Name
5. Коммерция: да (запрещено только продавать сам шрифт)
6. В игре атрибуция не нужна. В сборку кладём `OFL.txt` с копирайтом: «Copyright 2015 the Cormorant Project Authors», «Copyright 2020 The Inter Project Authors»
7. Ограничения: нет. Cormorant тонкий: только веса 600–700 и только для заголовков
8. TTF (SC — статические, Inter — variable)
9. —. Кириллица полная (cyrillic, cyrillic-ext)
10. PBR: —
11. Полигонаж: —
12. LOD / коллизии / риг / анимации: —
13. Стиль: Cormorant SC 8/10 — «инскрипционная» капитель как у Cinzel, но с кириллицей. Inter 9/10 по читаемости.
14. Inter остаётся. Для H1 и заголовков экранов переходим с Cormorant на Cormorant SC 600–700. Табличные цифры Inter (tnum) уже используются в проекте (`ui_tokens.gd`).

---

## Резерв
Проверены, но в рекомендованный набор не входят.

| # | Ассет | Лицензия | Зачем держать | Минусы |
|---|---|---|---|---|
| R1 | Marble 01, Rob Tuytel — https://polyhaven.com/a/marble_01 | CC0 | полный набор карт для пола (Diffuse, nor_gl, Rough, AO, Disp, ARM), 1K–8K, кремовый тон | прямоугольные плиты со смещением не совпадают с сеткой клеток |
| R2 | game-icons.net (4180 иконок, 36 авторов) — https://game-icons.net/ | CC BY 3.0, атрибуция по каждому автору («Icons made by {author}. Available on https://game-icons.net») | крупные фэнтезийные бейджи: типы врагов, стихии, спец-башни. Закрыто 27 из 28 понятий | у разных авторов разный стиль; залитые силуэты не сочетаются с линиями Lucide. Смешивать в одном HUD нельзя |
| R3 | TaleTone «Fantasy Window Frames – Antique & Alchemy Frames Sample» — https://store.godotengine.org/asset/taletone/window-frames-free/ | CC BY 4.0 | SVG и PNG 1024, 9-slice — референс для своих рамок | всего 2 дизайна, «алхимическая» сказочность, версия помечена unstable |
| R4 | Single Stone 6-Prong Wedding Band, EristoffJewelryDesigns — https://sketchfab.com/models/85c4e6dc7c8f4e1e9d7f8a234e1be9c6 | CC BY 4.0 | головка с шестью крапанами — оправа для гемов качества V | CAD под литьё, 27 326 граней, нужно вырезать и упростить |
| R5 | Forest Monster, CDmir — https://opengameart.org/content/forest-monster | CC0 | временный Живучий (тролль с деревом на спине) | 2015 год, только diffuse, normal и AO, клипы не названы |
| R6 | Living Flesh Blob, Yury Misiyuk (Tim0) — https://sketchfab.com/models/6357bbc094d54cf5ba150ef2951b3750 | CC BY | временный Раскольник: 9 936 треугольников, 1K PBR | только анимация пульсации |

## Отказы
| Ассет | Причина |
|---|---|
| Quaternius Ultimate Monsters (CC0 на странице пака; новые паки — QAL v1.0, не CC0) | low-poly — именно этот стиль мы заменяем |
| KayKit | стилизованный стиль; страница в этой сессии отдала 404 |
| Floor Tiles 06 (Poly Haven, CC0) | коричнево-бежевая шахматка спорит с путём и подсветкой клеток |
| Coastal Cliff 01 (Poly Haven, CC0) | 865 917 треугольников, ≈92 м, трава и мох по краю |
| Free Dark Fantasy Stone Statue, Pedestal, and Sword (Fab) | только пакет UE 5.5–5.8, геометрия под Nanite |
| Pedestal Delphic complex (Fab, CC BY 4.0) | сырой скан на 1.65M полигонов с землёй и обломками |
| Classic Gemstone Cuts, vincentsnow_art (Sketchfab) | **CC-BY-SA**, по §6(a) EULA Fab нельзя совмещать с ассетами Fab |
| Demonic Spider, PolyReady (Fab) | в бесплатной версии только idle; на карточке «Generated with AI: Yes» |
| Сомнительные заливы Sketchfab: Doctor A. («Tarisland – Dragon», «Achates (Lost Ark)» и др.), «wyvern by protofactor on reallusion», «… Elder Scrolls Blades … Troll» | метка CC-BY при видимом происхождении из коммерческих игр или магазинов — права залившего сомнительны |
| Kenney Smoke Particles и Kenney Fantasy UI Borders (CC0) | мультяшный дым; ступенчатые пиксельные орнаменты — не cinematic |
| Dark Relics UI (itch.io) | лицензия не указана, платно ($19.95) |
| Cinzel, Marcellus (OFL) | нет кириллицы |

---

## Сводка

### Рекомендуемый набор
| Слот | Выбор | Лицензия |
|---|---|---|
| Пол арены | E1 Tiles 139 (запасной E2 Travertine 009) | CC0 |
| Стены | E4 Moon Rock 02 (упростить до ≈600 треуг.) + материал E3 Rock 035 + шейдер обсидиана | CC0 |
| Бездна | E5 Boulder 01 (острова) + E6 Rock Face 01 (массы), тонировка в тёмный | CC0 |
| HDRI | E7 Kloppenheim 07 — арена; E8 Qwantani Night — меню | CC0 |
| Пьедесталы и ориентиры | E9 Pedestal Type C (гемы) + E10 Stone Pillar (чекпоинты, портал) | CC BY 4.0 / Fab |
| Гемы | G1 Gems 21 shapes + G2 кабошон для опала (+R4 оправа для V — по желанию) | CC BY 4.0 |
| Рядовые враги | C1 HighPolyDensity (Бронированный, Щитоносец, Рой) + C3 Ferocious (Быстрый, Ходок, Заговорённый) + C5 Vampire Bat (Летающий) | CC BY 4.0 / CC0 |
| Боссы | C7 Golem (Страж) + C2 Queen и Stonewisp (Матка, Левиафан) + C9 DemonLord2 (Король) + C6 Troll (Колосс) | Fab / CC BY 4.0 |
| VFX | V1 Kenney Particle Pack + V2 Unity Labs flipbooks | CC0 |
| UI | U1 Lucide + U2 Cormorant SC и Inter; 9-slice рамки — свои SVG | ISC/MIT / OFL |

### Пробелы
- **Живучий:** нет хорошего бесплатного. Варианты: временно R5, или платный Corrupted Ent (Alexander Lenski, ≈₸23 675), или перекрас Pteran из C1.
- **Раскольник и Осколок:** только R6 с одной анимацией. Осколки — процедурные кристаллы с теми же шейдерами, что у гемов. Это оправдано, они «из того же камня».
- **Прислужник** (бес или череп): ничего не найдено. Предлагаю уменьшенный и перекрашенный Blight Drone из C1 или гуманоида с Mixamo.
- **Death-клипы:** у C1 и Queen их нет. В игре смерть уже показывается как dissolve с осколками, поэтому клип не обязателен.
- **Цитадель на выходе:** готовой нет. Собираем из колонн E10, блоков стен и крупного гема G1 — у нас есть все части.

### Что делаем сами
- **9-slice рамки UI** в SVG по токенам: латунная линия `#C9A45C`, панель `#0E1119`, состояния normal, hover, pressed, disabled, focused.
- **Шейдеры:** обсидиан с жилами, преломление и дисперсия гемов, VAT-плеер для врагов в MultiMesh.
- **Конвейер подготовки:**
  - запекание VAT;
  - упрощение мешей;
  - перевод карт в ORM;
  - пересжатие текстур 4K → 2K и 1K.

  Нужен Blender — его тоже нужно поставить; спрошу отдельно.

### Лицензионные риски
- **CC-BY-SA в наборе нет.** Classic Gemstone Cuts отклонён: его нельзя совмещать с Fab.
- **CC BY 4.0** (C1–C4, C6, E9, G1, G2, R4, R6) — атрибуция в [CREDITS.md](CREDITS.md), `assets/LICENSES.md` и на экране «Авторы».
- **Fab Standard License** (C7, C9, E10):
  - сырые файлы нельзя публиковать: репозиторий `M3etis/GemTD` сейчас приватный, при открытии их придётся убрать;
  - нельзя давать игрокам извлекать ассеты (касается функции «подмена звуков без пересборки» — на модели её не распространяем).
- **DemonLord2 бесплатен только в тире Personal** (≤$100K выручки или финансирования за 12 мес.). Подтверди, что проект подходит.
- **Mixamo** (анимации для Shadowkin): по официальному FAQ — royalty-free для игр. Запрет раздавать сырые файлы подтверждён только неофициальным пересказом; репозиторий приватный, поэтому риск низкий.
- **Правило проекта §3** (только CC0 и OFL) при выборе любых не-CC0 ассетов расширяется записью в `docs/DECISIONS.md`.

### Что нужно от тебя
1. **Выбор:** принять рекомендуемый набор целиком или заменить отдельные слоты (номера E/C/G/V/U/R).
2. **Сегодня до 19:59** — если C7 Golem нужен, добавь его в свою библиотеку на Fab.
3. **Скачивание из Sketchfab и Fab** требует входа в аккаунт. Пароли я не ввожу: либо скачаешь архивы сам в `~/Downloads/gtd_assets/`, либо войдёшь в браузерной панели, а я скачаю после твоего подтверждения. Poly Haven, ambientCG, Kenney, Unity Labs и Lucide скачиваются без входа.
4. **Подтверждение тира Personal** для DemonLord2.

## Замены ассетов Fab (03.11.2026)

C7 Golem и C9 DemonLord2 заменены: Fab Standard License запрещает распространять ассет отдельно от продукта. Решение и отброшенные варианты — `docs/DECISIONS.md` §104.

| ID | Ассет | Автор | Лицензия | Роль | Клипы | Треугольники |
|---|---|---|---|---|---|---|
| C10 | Infernal Magma Hound — https://sketchfab.com/3d-models/bd8290074df34eb99f174edb176fcc46 | Yury Misiyuk | CC BY 4.0 | Каменный Страж | Idle, Walk | 12 538 → 3 134 |
| C11 | Armored Guard Knight Rig — https://sketchfab.com/3d-models/b7bba7eddb13470b88eb8b24531cb6b3 | DM-913 | CC BY 4.0 | Обсидиановый Король | Idle (+ ходьба и смерть из A1) | 21 433 → 5 353 |
| A1 | Universal Animation Library, Standard — https://quaternius.itch.io/universal-animation-library | Quaternius | CC0 1.0 | ходьба и смерть Короля и Заговорённого | 45 клипов, взяты Walk_Loop и Death01 | — |
