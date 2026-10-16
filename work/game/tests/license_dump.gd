extends SceneTree

func _initialize() -> void:
	var text := "GODOT ENGINE\n\n"+Engine.get_license_text()+"\n\nTHIRD-PARTY LICENSE TEXTS\n\n"
	var licenses := Engine.get_license_info()
	for name in licenses:
		text += "\n=== "+str(name)+" ===\n"+str(licenses[name])+"\n"
	text += "\nTHIRD-PARTY COPYRIGHT NOTICES\n\n"+JSON.stringify(Engine.get_copyright_info(),"  ")
	var file := FileAccess.open("user://GODOT-LICENSES.txt",FileAccess.WRITE)
	file.store_string(text)
	print(ProjectSettings.globalize_path("user://GODOT-LICENSES.txt"))
	quit()
