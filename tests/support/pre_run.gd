extends GutHookScript
## Runs before the tests: they expect the English texts, whatever the machine's language.


func run() -> void:
	TranslationServer.set_locale("en")
