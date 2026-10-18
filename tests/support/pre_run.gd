extends GutHookScript
## Runs before the tests: they expect the English texts, whatever the machine's language, and never
## load or write a save (tests of saving set `SaveGame.directory` themselves). The map starts
## without the title view and doesn't pause when the window loses focus (tests of those turn them
## on themselves). Engine warnings that say nothing about the code under test don't fail a test
## (`expected_engine_warnings.gd`).

const EXPECTED_ENGINE_WARNINGS := preload("res://tests/support/expected_engine_warnings.gd")


func run() -> void:
	TranslationServer.set_locale("en")
	SaveGame.directory = ""
	TitleView.shows = false
	PausePanel.pause_on_focus_loss = false
	EXPECTED_ENGINE_WARNINGS.instance = EXPECTED_ENGINE_WARNINGS.new()
	OS.add_logger(EXPECTED_ENGINE_WARNINGS.instance)
