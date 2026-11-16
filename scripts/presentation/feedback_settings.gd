extends RefCounted
var config_path: String = "user://feedback.cfg"
var volume: float = 0.7
var shake: float = 0.65
var flash: float = 0.65

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK: return
	for key: String in ["volume", "shake", "flash"]:
		var value: Variant = config.get_value("combat", key, get(key))
		if (value is float or value is int) and is_finite(float(value)): set(key, clampf(float(value), 0, 1))

func save_settings() -> Error:
	var config := ConfigFile.new()
	for key: String in ["volume", "shake", "flash"]: config.set_value("combat", key, get(key))
	return config.save(config_path)
