@tool
extends SceneTree

func _init() -> void:
	print("==================================================")
	print("--- COMPILING ALL 3D ASSETS INTO IMPORT CACHE ---")
	print("==================================================")
	
	var dir_queue := ["res://assets"]
	var files_to_process: Array[Dictionary] = []
	
	while not dir_queue.is_empty():
		var current_dir_path: String = dir_queue.pop_front()
		var dir := DirAccess.open(current_dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if not file_name.begins_with("."):
					dir_queue.append(current_dir_path + "/" + file_name)
			elif file_name.ends_with(".import"):
				var import_path := current_dir_path + "/" + file_name
				var cfg := ConfigFile.new()
				var err := cfg.load(import_path)
				if err == OK:
					var importer: String = cfg.get_value("remap", "importer", "")
					var type: String = cfg.get_value("remap", "type", "")
					var dest_path: String = cfg.get_value("remap", "path", "")
					var source_file: String = cfg.get_value("deps", "source_file", "")
					
					if (type == "PackedScene" or importer == "scene") and dest_path.ends_with(".scn"):
						files_to_process.append({
							"import_path": import_path,
							"source_file": source_file,
							"dest_path": dest_path
						})
			file_name = dir.get_next()
		dir.list_dir_end()
	
	print("Found %d 3D model import files to process." % files_to_process.size())
	
	var success_count := 0
	var error_count := 0
	
	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute("res://.godot/imported")
	
	for entry in files_to_process:
		var src: String = entry["source_file"]
		var dst: String = entry["dest_path"]
		
		if not FileAccess.file_exists(src):
			print("SKIP (Source not found): ", src)
			continue
			
		print("Processing: ", src.get_file())
		
		var node: Node3D = null
		if src.get_extension().to_lower() == "fbx":
			var doc = ClassDB.instantiate("FBXDocument")
			var state = ClassDB.instantiate("FBXState")
			var append_err = doc.append_from_file(src, state)
			if append_err == OK:
				node = doc.generate_scene(state)
			else:
				print("  ERROR appending FBX: code %d" % append_err)
		elif src.get_extension().to_lower() in ["glb", "gltf"]:
			var doc = ClassDB.instantiate("GLTFDocument")
			var state = ClassDB.instantiate("GLTFState")
			var append_err = doc.append_from_file(src, state)
			if append_err == OK:
				node = doc.generate_scene(state)
			else:
				print("  ERROR appending GLTF: code %d" % append_err)
		
		if node != null:
			var packed := PackedScene.new()
			var pack_err = packed.pack(node)
			if pack_err == OK:
				var save_err = ResourceSaver.save(packed, dst)
				if save_err == OK:
					print("  -> COMPILED OK: ", dst.get_file())
					success_count += 1
				else:
					print("  ERROR saving .scn: code %d" % save_err)
					error_count += 1
			else:
				print("  ERROR packing node: code %d" % pack_err)
				error_count += 1
			node.queue_free()
		else:
			print("  ERROR: generate_scene produced null for ", src)
			error_count += 1
	
	print("==================================================")
	print("DONE! Compiled: %d | Errors: %d" % [success_count, error_count])
	print("==================================================")
	quit(0)
