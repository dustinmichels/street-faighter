# Make your own fighter

You describe a fighter in the game. The game turns your answers into a **creator kit**: a folder with instructions for your own AI coding agent. The agent builds the fighter in Blender, checks it, and exports a `.glb` model. You import it, and it's your fighter against the CPU and online.

The game never runs Blender or the agent for you, and nothing is uploaded anywhere: the kit, the agent, and Blender all run on your computer.

## Before you start

- **Blender 4.2 or newer.** [Download Blender](https://www.blender.org/download/) and install it normally (on macOS, drag it into Applications). The agent finds it on its own. Without Blender, the agent can fall back to Blender's Python module from PyPI.
- **An AI coding agent that runs shell commands**, installed and signed in. The game has one-click commands for:
  [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
  [Codex](https://developers.openai.com/codex/cli),
  [Gemini CLI](https://geminicli.com),
  [Antigravity CLI](https://antigravity.google/docs/cli/using),
  [Pi](https://pi.dev), and
  [Oh My Pi](https://omp.sh). Any other agent works too.
- **A terminal.** On macOS: **Applications → Utilities → Terminal**.

## 1. Describe your fighter

Menu → **CHARACTERS** → **CREATE NEW**. Eight short pages:

| Page               | You choose                                                                                                            |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| **WHO IS IT?**     | A name and a one-line concept ("A french lizard man").                                                                |
| **ARCHETYPE**      | Brawler, martial artist, wrestler, boxer, robot, monster, street punk, knight, ninja, animal, or your own.            |
| **BUILD**          | Slim, athletic, heavy, or huge.                                                                                       |
| **HEAD**           | Human, helmet, mask, animal, or robot, plus any headwear.                                                             |
| **OUTFIT**         | Top, bottom, and footwear, each from a list or described in your own words.                                           |
| **PALETTE**        | Four colors: main, secondary, accent, and skin / base. Start from a preset or pick your own.                          |
| **ACCESSORIES**    | Any of belt, gloves, shoulder pads, scarf, backpack, tail, cape, knee pads, headband, sunglasses, chain, wrist wraps. |
| **ANYTHING ELSE?** | Free notes for the agent.                                                                                             |

## 2. Save the kit

**STEP 1 OF 3: SAVE THE KIT** shows the prompt your agent will get. Press **SAVE KIT**.

The kit goes to `~/Documents/street-fAIghter characters/<name>/` (one folder per fighter). **FOLDER…** picks a different place.

## 3. Run your agent

**STEP 2 OF 3: RUN YOUR AGENT**:

1. Press **AGENT** until it shows the agent you use. The game copies a command to your clipboard, like:

   ```sh
   cd '/Users/you/Documents/street-fAIghter characters/jim_bean' && claude 'Read PROMPT.md and follow it.'
   ```

2. Open a terminal, paste the command, and press <kbd>Enter</kbd>. Your agent starts inside the kit folder and reads its instructions.

**COPY COMMAND** copies it again, **COPY PROMPT** copies the instructions themselves (for an agent you've already started), and **OPEN FOLDER** shows the kit in Finder.

The agent then works on its own. It finds Blender, writes a Python script that builds the fighter on the game's skeleton, renders preview images to check its work, exports `<name>.glb`, and runs the game's own validator until the model passes. Depending on your agent's settings, it may ask you to approve the commands it runs. When it's done, it prints the path of the `.glb`.

![A preview render of Jim Bean, made by the agent](/media/jim-bean-render.png){width=320}

_One of the agent's preview renders, saved in the kit's `previews/` folder._

## 4. Import

Press **NEXT** to reach **STEP 3 OF 3**. The game looks for the kit's `.glb` every second and enables **IMPORT** as soon as it's there. Press it.

You can also come back later with **CHARACTERS → IMPORT…**, pick any `.glb` with **BROWSE…**, or drag a `.glb` onto the game window.

The game checks the model again before adding it. If something is wrong, **IMPORT FAILED** lists every problem. Press **COPY ERRORS**, paste them to your agent, and import again once it has fixed them.

## 5. Fight

Your fighter is now in the **CHARACTERS** library, where it turns in place with the in-game look. **PUNCH** plays the punch, to check that every part follows the arm. Choose it on **CHOOSE YOUR FIGHTER** (**1 PLAYER VS CPU**) and press **FIGHT!**. The fighter you last chose is also the one you play [online](./online), where your opponent's game downloads it automatically.

## Changing a fighter

Ask your agent for changes in the same session (or start it again in the kit folder). Once it has exported again, select the fighter in **CHARACTERS** and press **RE-IMPORT**.

**DELETE** removes a fighter from the library. The kit folder and its `.glb` stay where they are.

## Rules every fighter follows

Fighters are **cosmetic**: hitboxes, reach, speed, and damage are the same for everyone, whatever the model looks like. The game owns all animations and plays them on one shared skeleton. To be accepted, a model must:

- use the game's 17-bone skeleton unchanged, with each body part a rigid piece attached to one bone,
- stand 1.6–2.0 m tall with its feet on the ground,
- stay within 10,000 triangles, a 4 MB file, and two textures of at most 1024×1024,
- use opaque materials only (no see-through parts).

The agent's instructions cover all of this; you shouldn't need to know it. The full contract is in [Skeleton](/dev/skeleton) and the [character pipeline](/dev/custom-characters).

## Checking a model by hand

The kit's `PROMPT.md` contains the exact validator command for your copy of the game. For the macOS app in Applications, it's:

```sh
/Applications/street-faighter.app/Contents/MacOS/street-faighter --headless -- --validate-character /absolute/path/to/fighter.glb
```

It prints `OK`, or one problem per line.
