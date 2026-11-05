#!/bin/zsh
# Автотест мультиплеера: два headless-процесса с ботами играют матч «Гонка» по localhost.
# Успех: оба печатают MP-OK (итоговая таблица получена, свой реплей и реплики соперника сошлись).
# Использование: tools/mp_selftest.sh [волн=5] [порт=7790]
# Собранная игра вместо проекта: GTD_BIN="build/Gem Tower Defense.app/Contents/MacOS/Gem Tower Defense" tools/mp_selftest.sh
# Долгая загрузка сцены матча у одного из игроков (секунды): HOST_STALL=12 или GUEST_STALL=12 — соединение не должно рваться.
cd "$(dirname "$0")/.."
WAVES=${1:-5}
PORT=${2:-7790}
LOG=$(mktemp -d)
if [[ -n "$GTD_BIN" ]]; then RUN=("$GTD_BIN"); else RUN=("${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}" --path .); fi
HOST_EXTRA=(); GUEST_EXTRA=()
[[ -n "$HOST_STALL" ]] && HOST_EXTRA=(--load-stall=$HOST_STALL)
[[ -n "$GUEST_STALL" ]] && GUEST_EXTRA=(--load-stall=$GUEST_STALL)
"${RUN[@]}" --headless --fixed-fps 30 -- --mp-host --port=$PORT --name=Host --bot --waves=$WAVES --seed=4242 "${HOST_EXTRA[@]}" > "$LOG/host.log" 2>&1 &
HOST_PID=$!
sleep 2
"${RUN[@]}" --headless --fixed-fps 30 -- --mp-join=127.0.0.1 --port=$PORT --name=${GUEST_NAME:-Guest} --bot "${GUEST_EXTRA[@]}" > "$LOG/guest.log" 2>&1 &
GUEST_PID=$!
for i in {1..240}; do
  if ! kill -0 $HOST_PID 2>/dev/null && ! kill -0 $GUEST_PID 2>/dev/null; then break; fi
  sleep 1
done
kill $HOST_PID $GUEST_PID 2>/dev/null
echo "== host";  grep -E "^mp-|^MP-|SCRIPT ERROR|ERROR" "$LOG/host.log"
echo "== guest"; grep -E "^mp-|^MP-|SCRIPT ERROR|ERROR" "$LOG/guest.log"
if grep -q "^MP-OK" "$LOG/host.log" && grep -q "^MP-OK" "$LOG/guest.log"; then
  echo "РЕЗУЛЬТАТ: OK (логи: $LOG)"; exit 0
fi
echo "РЕЗУЛЬТАТ: FAIL (логи: $LOG)"; exit 1
