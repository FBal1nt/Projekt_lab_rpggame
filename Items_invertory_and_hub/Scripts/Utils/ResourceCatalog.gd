extends RefCounted

## Shared recursive scanner for data-driven .tres/.res resources.
## Keep resource discovery in one place so all systems use the same rules.


static func collect_resource_paths(root_directory: String) -> Array[String]:
	var paths: Array[String] = []
	_append_resource_paths(root_directory, paths)
	paths.sort()
	return paths


static func _append_resource_paths(directory_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			if not entry.begins_with("."):
				_append_resource_paths(directory_path.path_join(entry), output)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			output.append(directory_path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
