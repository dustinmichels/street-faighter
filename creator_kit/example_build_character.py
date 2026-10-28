"""Worked example: a simple brawler built with kit.py, exported as example.glb.

Copy it to build_character.py, replace the parts, and drop glb="example.glb" from finish()
(the kit's kit_config.json names the export). Run from this folder:
    blender -b --factory-startup --python example_build_character.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # Blender doesn't add it
sys.dont_write_bytecode = True  # keep __pycache__ out of the kit folder
from kit import *  # noqa: E402,F403

start()

# sRGB colors, as a color picker shows them. The game shows exactly these.
material("skin", "#e0a878")
material("hair", "#2a1a10")
material("eyes", "#f4f4f4")
material("shirt", "#c02a20")
material("pants", "#2a2c38")
material("shoes", "#181410")

# Torso: boxes that overlap where the bones meet.
box("hips", "shorts", "pants", (-0.16, -0.10, 0.86), (0.16, 0.10, 1.07))
box("spine", "belly", "shirt", (-0.15, -0.095, 1.03), (0.15, 0.095, 1.27))
box("chest", "shirt", "shirt", (-0.21, -0.115, 1.25), (0.21, 0.115, 1.49))
cylinder("neck", "neck", "skin", (0, 0, 1.44), (0, 0, 1.57), 0.05)

# Head with a face (eyes, nose) on the -Y side, so the facing reads at low resolution.
sphere("head", "skull", "skin", (0, 0, 1.67), (0.11, 0.12, 0.13))
sphere("head", "hair", "hair", (0, 0.025, 1.70), (0.118, 0.115, 0.115))
sphere("head", "eye", "eyes", (0.045, -0.11, 1.68), 0.022, mirror=True)
box("head", "nose", "skin", (-0.018, -0.145, 1.63), (0.018, -0.11, 1.67))

# Limbs: capsules from joint to joint cover the joints, so bent limbs show no gaps.
# mirror=True adds the .R copy.
for bone, mat, radius in (
    ("upper_arm.L", "shirt", 0.065),
    ("forearm.L", "skin", 0.055),
    ("thigh.L", "pants", 0.08),
    ("shin.L", "pants", 0.065),
):
    capsule(bone, "limb", mat, head(bone), tail(bone), radius, mirror=True)
sphere("hand.L", "fist", "skin", (0.76, 0, 1.42), (0.07, 0.06, 0.06), mirror=True)
box("foot.L", "shoe", "shoes", (0.04, -0.21, 0.0), (0.16, 0.06, 0.10), mirror=True)

finish("Example", "A red-shirted street brawler.", glb="example.glb")
