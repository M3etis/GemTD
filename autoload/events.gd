extends Node
## Глобальная шина событий уровня приложения (UI, настройки, переходы).
## Игровые события симуляции идут через GameSim.drain_events() — см. scenes/game.

signal settings_changed(section: String)
signal locale_changed(locale: String)
signal toast_requested(text: String, kind: String)
signal audio_reloaded(report: Array)
signal leaderboard_updated(record_id: String)
