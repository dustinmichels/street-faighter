# Special throw

A special is the character's own throw animation. When this character lands its grab, the game plays the special on both fighters instead of the standard throw: the thrower (the attacker) and the fighter it throws (the victim). Only the look changes. The timing, the damage, and where the victim lands stay the same as for every other fighter, so a special can't make the character stronger.

You add it to `build_character.py` with one call to `special()` before `finish()`. `finish()` saves it in the `.glb`, renders `previews/special.png`, and the game's validator checks it. Without a `special()` call the character uses the standard throw.

## Timeline

Ticks are the game's frames, 60 per second, counted from the tick the grab connects. The numbers come from `special_base.json` (the game writes it into this kit):

| Tick  | What happens                                                                                                                            |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------- |
| 0     | The grab connects: the thrower in its grab pose (`GRAB`), the victim standing 0.6 m in front of it.                                     |
| 0–43  | Your attacker keys.                                                                                                                     |
| 0–25  | Your victim keys: lift, flight, the way down.                                                                                           |
| 26    | The slam. The game puts the victim flat on its back on the floor, 1.3 m behind the thrower (root `[-1.3, 0]`), head toward the thrower. |
| 26–84 | The game's keys for the victim: it bounces (30), lies still (34–52), sits up (64), crouches (74), and stands (84).                      |
| 44    | The throw ends: the game puts the thrower back in its fighting stance (`STANCE`).                                                       |

The standard throw for comparison: lifted by 8, overhead at 16, coming down at 22, slammed at 26.

## Frames and the root

- **The thrower** stays where it stands; it only bends and moves its hips (`hips_pos`). Its "forward" is toward the victim.
- **The victim** always faces the thrower. Its body is placed by `root = (forward, up)` in meters: where its feet would be at rest, measured from the thrower's feet, forward along the thrower's facing and up. `(0.6, 0)` is standing in front of the thrower, `(0, 1.5)` is over its head, `(-1.3, 0)` is on the floor behind it. Start your first victim key at `(0.6, 0)`, where the grab caught it, so it doesn't jump.
- The victim's body turns around its `hips` joint, 0.95 m above the root (plus `hips_pos`). Flips and spins go on `hips`: everything else hangs from it. Upside down at `root` up 1.6, the hips are at 2.55 m and the head about 0.8 m lower.
- The victim's bones use its own axes. Its forward is toward the thrower: victim `hips` +X tips its head toward the thrower (a forward flip, like the standard throw), −X tips it backward, feet first toward the thrower.

## Poses

A pose is a dict, the same as the game's own animations use:

```python
{"spine": (10, 0, 0), "upper_arm.L": (40, 0, -20), "hips_pos": (0, -0.2, 0.05)}
```

- A bone maps to an `(x, y, z)` rotation in degrees, relative to its rest pose (the T-pose), in the bone's own axes. Several axes combine like Blender's `Euler((x, y, z) in radians, 'ZXY')` on the bone (the game's YXZ order); one or two axes per bone is easiest to reason about.
- `"hips_pos"` is `(x, y, z)` meters added to the hips' rest position: x = the body's left, y = up, z = forward. It moves the whole body (crouch, lean in) without turning it.
- **Unlisted bones snap back to the T-pose.** Build every pose from `STANCE` or `GRAB` with `pose(base, changes)`.

Axis cheat sheet (SKELETON.md, "Bone axes"):

| Bones                                    | +X                                     | Y                        | Z                       |
| ---------------------------------------- | -------------------------------------- | ------------------------ | ----------------------- |
| `hips`, `spine`, `chest`, `neck`, `head` | bends forward (−X: back)               | +Y turns toward its left | +Z leans to its right   |
| `thigh.*`                                | swings the leg back (−X: knee forward) | twists the leg           | swings the leg sideways |
| `shin.*`                                 | bends the knee                         |                          |                         |
| `foot.*`                                 | points the toes down                   |                          |                         |
| `upper_arm.*`, `forearm.*`, `hand.*`     | raises the arm (−X: lowers it)         | twists the arm           | −Z swings it forward    |

Write the `.L` value and use `mirror(v)` for the `.R` bone: the same numbers then mean the same motion on both sides. For example `STANCE` holds the fists up with `upper_arm.L` `(-75, 0, -20)`, `forearm.L` `(0, 0, -135)`; `GRAB` reaches both arms forward with `upper_arm.L` `(-15, 0, -75)`.

## Interpolation

Keys blend linearly, so the game plays exactly what the keys say:

- **Rotations turn the short way round.** From one key to the next, a bone turns by the smaller angle, never more than 180°. A flip needs in-between keys less than 180° apart (90° is safe): `0 → -90 → -180 → -270`, not `0 → -270`, which turns +90 instead.
- Angles must stay within ±360°. Past that, add or subtract 360: −420 is −60. Only the difference to the neighboring key matters.
- `hips_pos` and `root` move in straight lines between keys.
- Before your first key the first one holds, after your last key the game's next key takes over: the thrower blends from your last key into the stance at 44, and the victim from your last key into lying flat (`hips` −90, which is 270) at the landing spot on 26. Make your last victim key lead into that the short way, for example a forward flip at `hips` 230 or a backward one at −60.
- To hold a pose, repeat its key at a later tick.

## Limits

The validator checks these (its lines start with `Special:`):

- `attacker`: 1–64 keys, ticks whole numbers 0–43, each later than the one before.
- `victim`: 1–64 keys, ticks whole numbers 0–25, each later than the one before.
- Bone names from SKELETON.md, and `hips_pos`. Every angle within ±360°. `hips_pos` within ±2 m per axis.
- `root`: forward within ±3 m, up from −1 to 3 m.

## API

`from kit import *` gives:

| Name                        | What it is                                                                                                                                                       |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `special(attacker, victim)` | The special. `attacker`: a list of `(tick, pose)`. `victim`: a list of `(tick, pose, (forward, up))`. Call it once, before `finish()`; a later call replaces it. |
| `pose(base, changes)`       | A copy of pose `base` with the bones in `changes` set on top.                                                                                                    |
| `mirror(v)`                 | The `.R` value `(x, -y, -z)` for the `.L` value `v = (x, y, z)`.                                                                                                 |
| `STANCE`, `GRAB`            | The game's fighting stance (where the thrower ends) and grab pose (where it starts).                                                                             |
| `STANDARD_THROW`            | The standard throw as `special()` arguments: `special(**STANDARD_THROW)` plays it as a special. A working starting point.                                        |

`special_base.json` holds the same data, plus the game's victim keys after the slam (`after_slam`).

## Worked example

A catapult: the thrower squats, grabs the victim's legs, and heaves it up and over its own head feet first; the victim spins 1¼ backward somersaults and lands on its back behind the thrower. Paste it into `build_character.py` before `finish()`; it passes the validator as it is.

```python
def lr(bones):
    """`bones` with each .L bone's mirror() added as .R, so both sides move alike."""
    out = dict(bones)
    for name, v in bones.items():
        if name.endswith(".L") and name[:-2] + ".R" not in bones:
            out[name[:-2] + ".R"] = mirror(v)
    return out


# The thrower: squat and grab the thighs, drive up onto the toes with the arms overhead,
# follow through arched back and looking up, then settle while the victim lands.
dig = pose(STANCE, lr({
    "hips_pos": (0, -0.32, -0.08),
    "spine": (30, 0, 0), "chest": (15, 0, 0), "neck": (-25, 0, 0), "head": (-15, 0, 0),
    "upper_arm.L": (-25, 0, -80), "forearm.L": (0, 0, -15),
    "thigh.L": (-70, 0, 0), "shin.L": (100, 0, 0), "foot.L": (-30, 0, 0),
    "thigh.R": (-50, 0, 0), "shin.R": (95, 0, 0), "foot.R": (-45, 0, 0),
}))
lift = pose(dig, lr({
    "hips_pos": (0, -0.22, -0.05),
    "spine": (10, 0, 0), "chest": (5, 0, 0), "neck": (-15, 0, 0),
    "upper_arm.L": (30, 0, -60), "forearm.L": (0, 0, -20),
    "thigh.L": (-45, 0, 0), "shin.L": (70, 0, 0), "foot.L": (-25, 0, 0),
    "thigh.R": (-30, 0, 0), "shin.R": (65, 0, 0), "foot.R": (-35, 0, 0),
}))
heave = pose(STANCE, lr({
    "hips_pos": (0, 0.03, 0),
    "spine": (-10, 0, 0), "chest": (-8, 0, 0), "neck": (-20, 0, 0), "head": (-15, 0, 0),
    "upper_arm.L": (80, 0, -15), "forearm.L": (0, 0, -10),
    "thigh.L": (-12, 0, 0), "shin.L": (8, 0, 0), "foot.L": (25, 0, 0),
    "thigh.R": (5, 0, 0), "shin.R": (5, 0, 0), "foot.R": (30, 0, 0),
}))
arch = pose(heave, lr({
    "hips_pos": (0, -0.06, 0.08),
    "spine": (-22, 0, 0), "chest": (-15, 0, 0), "neck": (-20, 0, 0), "head": (-15, 0, 0),
    "upper_arm.L": (85, 0, 25), "forearm.L": (0, 0, -5),
    "thigh.L": (-25, 0, 0), "shin.L": (35, 0, 0), "foot.L": (-10, 0, 0),
    "thigh.R": (0, 0, 0), "shin.R": (25, 0, 0), "foot.R": (-25, 0, 0),
}))
watch = pose(STANCE, {"hips_pos": (0, -0.12, 0), "spine": (8, 0, 0), "neck": (-10, 0, 0)})

# The victim: lifted by the legs, flung up, spinning backward (-X on the hips) 1¼ turns.
# Keys are 55-90° apart: the game turns the short way between keys, so each key may move
# the spin less than 180°. Angles past ±360° are written minus 360 (-420 → -60).
grabbed = pose(STANCE, lr({
    "hips_pos": (0, 0.02, 0),
    "hips": (-5, 0, 0), "spine": (-10, 0, 0), "neck": (-15, 0, 0), "head": (-10, 0, 0),
    "upper_arm.L": (40, 0, 20), "forearm.L": (0, 0, -40),
    "thigh.L": (0, 0, -3), "shin.L": (5, 0, 0), "foot.L": (20, 0, 0),
}))
flung = pose(grabbed, lr({
    "spine": (-5, 0, 0), "neck": (5, 0, 0), "head": (0, 0, 0),
    "upper_arm.L": (10, 0, 30), "forearm.L": (0, 0, -30),
    "thigh.L": (-20, 0, -6), "shin.L": (30, 0, 0),
}))


def spin(degrees):
    return pose(flung, {"hips": (degrees, 0, 0)})


special(
    attacker=[(0, dig), (5, lift), (11, heave), (17, arch), (26, watch)],
    victim=[
        (0, grabbed, (0.6, 0.0)),
        (6, spin(-60), (0.5, 0.45)),
        (11, spin(-150), (0.3, 1.6)),
        (15, spin(-240), (-0.3, 1.75)),
        (19, spin(30), (-0.85, 1.35)),  # -330
        (23, spin(-60), (-1.2, 0.45)),  # -420; the game lands it flat (-450) on tick 26
    ],
)
```

The run prints, after `previews:`:

```
special: 5 attacker keys, 6 victim keys, saved in <slug>.glb
special: previews: …/previews/special.png (ticks 0, 6, 12, 18, 22, 26, 34, 43)
```

## Check, fix, repeat

`previews/special.png` shows the throw from the thrower's left side at ticks 0, 6, 12, 18, 22 (top row) and 26, 34, 43 (bottom row), each tile labeled with its tick. It plays the keys exactly as the game does, the game's own keys included. The thrower is in its colors, facing the image's left; the victim is a gray copy of the character; the dark line is the floor. Open it after every run and fix the script if you see:

- the victim turning the wrong way between two tiles (keys 180° or more apart: add an in-between key);
- the victim far from the thrower's hands while it is held, or its body sunk deep into the thrower's;
- the thrower's feet off the floor or sunk into it, where it should be standing (`hips_pos` y and the leg angles go together);
- limbs bent past what a body can do, or a bone left in the T-pose by a pose not built from `STANCE` or `GRAB`;
- the victim hitting the floor before tick 26, or still high up at 22 so it drops in a jerk;
- a motion that doesn't match what the player asked for.

Start from something that works: `special(**STANDARD_THROW)` or the example above, then change it step by step. Do at most **5** runs to fix how the special looks. If it still looks wrong after that, keep the best version and tell the player. Never stop before `RESULT: OK`. If the special itself can't pass, remove the `special()` call (the character then uses the standard throw) and tell the player.
