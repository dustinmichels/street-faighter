Here's how the pieces fit together:

This is very doable, and the most important design decision is to treat a character as two separate things: **the look** (a 3D model) and **the rules** (stats and abilities). The AI can have nearly total freedom over the look. The rules need to come from building blocks you define, and your server has to check them. Otherwise someone will just tell Claude "give my character 9999 damage," or edit the file afterward.

### The prompt is a contract

Your Godot questionnaire asks about concept, silhouette, colors, personality, and play style. Then it fills in a prompt template. The player's answers are the creative part. The rest of the template is fixed technical requirements that Claude has to follow: export as glTF 2.0 binary (`.glb`), stay under a triangle budget (say 8–15k), stand about 1.8 m tall, put the origin at the feet, face Blender's front view (−Y), apply all transforms, use at most two textures at 1024px, and use your exact bone names.

For abilities, the prompt includes your menu of ability types (projectile, dash, shield, heal, area effect…) with tiered parameters and a point budget. Claude's job is to translate "a fire knight who charges into battle" into those blocks and write the manifest:

```json
{
  "schema_version": 1,
  "name": "Ember Warden",
  "model": "ember_warden.glb",
  "stats": { "health": 3, "speed": 2, "armor": 1 },
  "abilities": [
    { "type": "dash", "distance_tier": 2, "cooldown_tier": 2, "vfx": "fire" },
    { "type": "projectile", "damage_tier": 2, "cooldown_tier": 1, "vfx": "fire" }
  ]
}
```

Use tiers, not raw numbers. Your server maps tiers to actual values and adds up the cost with its own table, so balance stays in your hands and you can rebalance later without breaking anyone's character.

### Rigging is the hard part

Claude can model a decent stylized character with code, but weight painting and animation from scratch are unreliable. Ship a template `.blend` file that contains your skeleton, and have the prompt tell Claude to build onto it. The most robust approach is to build the body from separate rigid parts, each parented to a bone, like an action figure or a PS1-era character. There's no weight painting, so it can't go wrong, and every animation just works. Keep all animations in your game, not in the uploaded file, and apply your own animation library to the imported skeleton by bone name. That also stops players from smuggling in weird animations that misrepresent their hitbox.

### Getting Claude into Blender

There are two routes, and I'd support both. The first is MCP, where Claude drives Blender directly. Blender's own developers have shipped an official MCP server through Blender Lab, which requires Blender 5.1 or newer. It connects an LLM client to a running Blender session through a companion add-on, exposing the Python API, docs, scene summaries, screenshots and code execution. The screenshots matter because Claude can look at its own work and fix it. There's also a popular community server, and the two can't run at the same time. Both listen on the same port.

The second route needs no setup. Claude writes a Blender Python script, and the player pastes it into Blender's Scripting tab and runs it. The script ends by exporting the `.glb`. This works with any chatbot, which is good if you want to be agent-agnostic.

In both cases, make your importer's error messages specific and paste-friendly, for example "Triangle count 23,410 exceeds 15,000; bone 'hand.L' missing." The player can then hand the error back to Claude to fix.

### Importing at runtime in Godot

An exported game can't use the editor's import pipeline, so you load player models with `GLTFDocument`:

```gdscript
func load_character(path: String) -> Node3D:
    var doc := GLTFDocument.new()
    var state := GLTFState.new()
    if doc.append_from_file(path, state) != OK:
        return null
    return doc.generate_scene(state)
```

One security point: only ever accept `.glb` from players, never `.tscn`, `.tres`, or `.res`. Godot resource files can contain scripts, so loading one from a stranger means running their code on every client.

### Multiplayer distribution

Have players upload over HTTP rather than pushing megabytes through RPCs. The server validates the file before anyone else ever sees it. It checks file size, triangle count, texture dimensions, bone names, and bounding box, and it recalculates the ability cost from the manifest. Then it stores the file under its SHA-256 hash. When a player joins a match, other clients get the hash, download the file if they don't have it cached, and show a default model in the meantime.

Two fairness rules help a lot. Hitboxes should be a standard capsule set by the server, not taken from the mesh, so a tiny or spindly character gains nothing. Also reject fully transparent materials and models below a minimum size. You'll also want a report button and an option for players to show default models instead of custom ones, because people will upload offensive things.

### A lighter alternative worth considering

Requiring Blender is real friction for most players. One variant skips it entirely: you build a library of parts in Godot (bodies, heads, armor, accessories, colors, proportions), and Claude only writes a JSON recipe that combines them. You get no file validation headaches, automatic rigging, tiny network payloads, and no security surface. The cost is less creative freedom. Many games would do well with the recipe system as the default and the full Blender pipeline as an advanced option for creators.

I can draft the actual prompt template, the full manifest schema with a cost table, or a GDScript mesh validator if you'd like to start building one of these.
