"""Export the open scene as a street-fAIghter character .glb, with fixed settings.

Call it at the end of your build script, after creating the parts:

    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # Blender doesn't add it
    from export_glb import export_glb
    export_glb(os.path.join(KIT, "my_fighter.glb"))

Don't call bpy.ops.export_scene.gltf yourself: these settings are part of the contract.
"""

import os

import bpy
from mathutils import Euler, Quaternion, Vector


def reset_pose():
    """Put every bone back at its rest pose, so a preview test pose can't end up in the file.

    Actions are removed too: with an action assigned, the depsgraph would re-apply its pose.
    """
    for obj in bpy.data.objects:
        if obj.type != "ARMATURE":
            continue
        if obj.animation_data:
            obj.animation_data_clear()
        for pb in obj.pose.bones:
            pb.location = Vector((0.0, 0.0, 0.0))
            pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
            pb.rotation_euler = Euler((0.0, 0.0, 0.0))
            pb.rotation_axis_angle = (0.0, 0.0, 1.0, 0.0)
            pb.scale = Vector((1.0, 1.0, 1.0))
    bpy.context.view_layer.update()


def export_glb(filepath):
    """Reset the pose and write `filepath` (.glb). Returns the absolute path."""
    filepath = os.path.abspath(filepath)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    reset_pose()
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",  # one binary file, textures embedded
        export_yup=True,  # +Y up, as glTF and Godot expect
        export_apply=True,  # apply modifiers: the file holds what the viewport shows
        export_animations=False,  # the game owns all animations
        export_morph=False,  # no shape keys
        export_cameras=False,
        export_lights=False,
    )
    print(f"exported {filepath}")
    return filepath
