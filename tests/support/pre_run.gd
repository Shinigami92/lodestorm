extends GutHookScript
## Runs before the tests: they expect the English texts, whatever the machine's language, and never
## load or write a save (tests of saving set `SaveGame.directory` themselves).


func run() -> void:
	TranslationServer.set_locale("en")
	SaveGame.directory = ""
