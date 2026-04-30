extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("CI smoke test: loading main scene")

	var main_scene_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))

	if main_scene_path.is_empty():
		push_error("application/run/main_scene is not set in project.godot.")
		quit(1)
		return

	var resource := ResourceLoader.load(main_scene_path)

	if resource == null:
		push_error("Could not load main scene: " + main_scene_path)
		quit(1)
		return

	if not (resource is PackedScene):
		push_error("Main scene is not a PackedScene: " + main_scene_path)
		quit(1)
		return

	var instance := (resource as PackedScene).instantiate()

	if instance == null:
		push_error("Could not instantiate main scene: " + main_scene_path)
		quit(1)
		return

	root.add_child(instance)

	await process_frame
	await process_frame

	print("CI smoke test: passed")
	quit(0)
