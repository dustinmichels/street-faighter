extends SceneTree

func _init() -> void:
	var root := CharacterLoader.load_character("res://characters/default/default.glb")
	var sk := CharacterLoader.find_skeleton(root)
	print("skel xform ", sk.transform, " parent ", sk.get_parent().transform)
	var lib: AnimationLibrary = load("res://animations/base.res")
	for clip in [&"air_kick", &"jump_air", &"punch"]:
		var a := lib.get_animation(clip)
		var t := a.get_marker_time(&"active_start") if a.has_marker(&"active_start") else a.length
		sk.reset_bone_poses()
		for i in a.get_track_count():
			var bone := sk.find_bone(String(a.track_get_path(i).get_concatenated_subnames()))
			if a.track_get_type(i) == Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(bone, a.position_track_interpolate(i, t))
			else:
				sk.set_bone_pose_rotation(bone, a.rotation_track_interpolate(i, t))
		var out := "%s@%.3f:" % [clip, t]
		for b in ["hips", "shin.L", "foot.L", "foot.R", "hand.R"]:
			var p := gpose(sk, sk.find_bone(b)).origin
			out += " %s=(%.2f, %.2f, %.2f)" % [b, p.x, p.y, p.z]
		var f := gpose(sk, sk.find_bone("foot.L"))
		out += " footL_y=%s" % str(f.basis.y.normalized())
		print(out)
	quit()


func gpose(sk: Skeleton3D, b: int) -> Transform3D:
	var t := sk.get_bone_pose(b)
	var p := sk.get_bone_parent(b)
	return t if p < 0 else gpose(sk, p) * t
