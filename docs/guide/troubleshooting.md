# Troubleshooting

## Installing

### "Apple could not verify street-faighter is free of malware"

The game isn't notarized by Apple. Open **System Settings → Privacy & Security**, click **Open Anyway** next to the message about street-faighter, and confirm. Full steps: [Download & install](./download#macos).

### "street-faighter is damaged and can't be opened"

The download's quarantine flag is confusing macOS. Clear it in Terminal, then open the app again:

```sh
xattr -dr com.apple.quarantine /Applications/street-faighter.app
```

### "Windows protected your PC"

The game isn't signed. Click **More info**, then **Run anyway**. Full steps: [Download & install](./download#windows).

If there's no **Run anyway** button, Smart App Control is blocking all unsigned apps. [Run the game from source](/dev/) instead.

### Linux: nothing happens when I open it

The file lost its executable flag. In a terminal, in the game's folder, run `chmod +x street-fAIghter.x86_64`, then start it again.

## Playing

### My keys do something else

Keys are bound by their position on a US QWERTY keyboard. On other layouts, use the keys in the positions of <kbd>W</kbd> <kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd>, <kbd>J</kbd> <kbd>K</kbd> <kbd>I</kbd>, and <kbd>Z</kbd> <kbd>X</kbd> <kbd>C</kbd>.

### The CPU is too hard

Press <kbd>F1</kbd> during a match for easy mode. See [The CPU](./playing#the-cpu).

## Online

The menu shows why a connection failed. Common messages:

| Message                                              | What it means                                                                                                                                                                                                        |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| _Could not connect to the host_                      | Nothing answered at that address. Check the IP and port, that the host pressed **HOST** first, and the host's [port forwarding](./online#port-forwarding) or firewall. On the same network, use the host's local IP. |
| _Game version mismatch (this game: …, other: …)_     | You're on different versions. Both install the [latest release](https://github.com/dustinmichels/street-faighter/releases/latest).                                                                                   |
| _Protocol version mismatch_                          | Same as above: different builds of the game.                                                                                                                                                                         |
| _Cannot host on UDP port …_                          | Another program, or another copy of the game, is using that port. Pick another port; the joiner then adds it: `IP:PORT`.                                                                                             |
| _Invalid address_ / _Invalid port_                   | Use `IP`, `IP:PORT`, or `[IPv6]:PORT`; ports are 1–65535.                                                                                                                                                            |
| _Connection lost: no data from the opponent for 5 s_ | The network dropped. Reconnect from the menu.                                                                                                                                                                        |
| _Desync at tick …_                                   | The two games disagreed about the match. Please [report it](https://github.com/dustinmichels/street-faighter/issues).                                                                                                |

### The match is laggy or slow

The game waits for your opponent's input every frame, so high ping slows the whole match down for both players. A wired connection, playing over a LAN, or choosing the player with the better connection as host helps. <kbd>F3</kbd> shows the network stats.

### My opponent shows up as the default fighter

Their model didn't arrive within 10 seconds, failed the validator, or you have **OPPONENTS: DEFAULT** turned on in the online menu. The match plays the same either way.

## Custom fighters

### The agent can't find Blender

Install [Blender](https://www.blender.org/download/) 4.2 or newer in the usual place (on macOS, `/Applications/Blender.app`), or tell the agent where it is. Without Blender, the kit's instructions let the agent use Blender's Python module from PyPI instead.

### IMPORT stays disabled

The game is waiting for `<name>.glb` in the kit folder. Check that your agent finished and printed the path. If the file is elsewhere, use **BROWSE…** or drag it onto the game window.

### IMPORT FAILED

Press **COPY ERRORS**, paste the list to your agent, and import again after it fixes the model. The messages are written for the agent.

### The validator command in PROMPT.md doesn't work

The kit records where the game was when it wrote the kit. If you moved the game since, tell your agent the new path (see [Checking a model by hand](./custom-characters#checking-a-model-by-hand)), or create a new kit from the game.

### My fighter shows up as the default model

A HUD notice says why: the library entry was deleted, or the file no longer passes the validator. Import it again from **CHARACTERS**.
