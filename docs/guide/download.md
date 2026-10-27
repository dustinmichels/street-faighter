# Download & install

Street fAIghter is free. Ready-made builds are for **macOS**; on Windows and Linux, [run it from source](/dev/) with the free Godot engine.

## What you need

| To…                         | You need                                                                                                                                       |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Play                        | A Mac with macOS 13 or newer (Apple silicon) or macOS 11 or newer (Intel). Keyboard, or any gamepad macOS recognizes.                          |
| Play online                 | A second player with the **same version** of the game, and a network path between you (same Wi-Fi, a VPN like Tailscale, or a forwarded port). |
| Make your own fighter       | [Blender](https://www.blender.org/download/) 4.2 or newer and an AI coding agent that runs in a terminal, such as [Claude Code](https://docs.anthropic.com/en/docs/claude-code). |

You can play right away; Blender and the agent are only needed when you [make a fighter](./custom-characters).

## Install on macOS

1. Open the [latest release](https://github.com/dustinmichels/street-faighter/releases/latest) on GitHub and download the macOS `.zip` under **Assets**.
2. Double-click the `.zip` in your Downloads folder. It unpacks to **street-faighter.app**.
3. Drag **street-faighter.app** into your **Applications** folder.

   ::: warning Move it before you open it
   Don't run the game straight from Downloads. macOS then runs it from a temporary, randomized location, and the creator kits the game writes would point your AI agent at a path that no longer exists after a restart.
   :::

4. Double-click the app. The first time, macOS says it can't verify the app and won't open it. The game is free and not registered with Apple, so it isn't notarized. Click **Done**, then:
   1. Open **System Settings → Privacy & Security**.
   2. Scroll down to the message about **street-faighter** and click **Open Anyway**.
   3. Confirm with your password or Touch ID, then click **Open Anyway** once more.

   macOS remembers the choice; from now on the app opens like any other.

::: details Prefer the terminal?
This clears the "downloaded from the internet" flag, which skips the prompt above:

```sh
xattr -dr com.apple.quarantine /Applications/street-faighter.app
```
:::

When you first host an online match, macOS may ask whether **street-faighter** may accept incoming network connections, or find devices on your local network. Click **Allow**; otherwise your opponent can't reach you.

## First launch

1. At **PRESS START**, press any key, click, or press a gamepad button.
2. Type your name (up to 10 characters) and press <kbd>Enter</kbd>.
3. Choose **1 PLAYER VS CPU** to fight the computer, or **2 PLAYERS ONLINE** to [play a friend](./online).

The moves and controls are on [How to play](./playing). In a match, <kbd>Esc</kbd> shows the controls at any time.

## Updating

Download the new release and replace the app in Applications. Your name, settings, and imported fighters are stored outside the app and carry over.

Online matches need both players on the same version: the game checks during the handshake and refuses a mismatch, with a message saying which versions met. The version is in the bottom-left corner of the title screen.

## Where your files are

| What                                                  | Where (macOS)                                                                 |
| ----------------------------------------------------- | ----------------------------------------------------------------------------- |
| Settings, imported fighters, fighters from opponents  | `~/Library/Application Support/Godot/app_userdata/street-faighter/`           |
| Creator kits (one folder per fighter you design)      | `~/Documents/street-fAIghter characters/` (changeable in the game)            |

To uninstall, delete the app and those two folders.
