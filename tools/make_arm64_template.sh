#!/bin/bash
# Экспорт-шаблон macOS только под arm64 (Apple Silicon) из официального universal-шаблона Godot.
# Официальный macos.zip содержит лишь universal-бинарники; пресет «macOS» с arm64 ждёт
# godot_macos_{release,debug}.arm64. Скрипт вырезает arm64-срез через lipo — приложение вдвое меньше.
# Запуск один раз после установки шаблонов: tools/make_arm64_template.sh
# Результат: build/templates/macos_arm64.zip (на него ссылается export_presets.cfg).
set -euo pipefail

GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
VERSION="$("$GODOT" --version | cut -d. -f1-4)"   # 4.7.2.stable.official.<hash> → 4.7.2.stable
SRC="$HOME/Library/Application Support/Godot/export_templates/$VERSION/macos.zip"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/templates/macos_arm64.zip"

if [[ ! -f "$SRC" ]]; then
	echo "Нет шаблонов экспорта $VERSION: $SRC" >&2
	echo "Установите их: редактор → Editor → Manage Export Templates → Download and Install." >&2
	exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$SRC" -d "$TMP"
BIN="$TMP/macos_template.app/Contents/MacOS"
for kind in release debug; do
	lipo "$BIN/godot_macos_$kind.universal" -thin arm64 -output "$BIN/godot_macos_$kind.arm64"
	rm "$BIN/godot_macos_$kind.universal"
done
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
(cd "$TMP" && zip -q -r -X "$OUT" macos_template.app)
echo "Готово: $OUT ($VERSION, arm64)"
