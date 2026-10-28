"""Build template.blend: the shared character skeleton (spec: SKELETON.md), for modeling by
hand. Build scripts don't need it: kit.py's start() builds the same skeleton (kit.py holds
the only bone list).

Writes template.blend next to this script, or to the path given after `--`:
    blender -b --factory-startup --python build_template.py
In the game repo (the game copies this file into every creator kit):
    blender -b --factory-startup --python creator_kit/build_template.py -- characters/template/template.blend
"""

import os
import sys

import bpy

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)  # Blender doesn't put the script's folder on sys.path
sys.dont_write_bytecode = True  # keep __pycache__ out of the kit folder
from kit import build_skeleton  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)
arm = build_skeleton().data

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = os.path.abspath(args[0]) if args else os.path.join(KIT, "template.blend")
bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
print(f"wrote {out} ({len(arm.bones)} bones)")
