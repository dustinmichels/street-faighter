# Download & install

Street fAIghter is free, with ready-made builds for **macOS**, **Windows**, and **Linux**. The easiest way to get it is the itch app, which installs it in one click and keeps it up to date. You can also download it from GitHub.

## What you need

| To…                   | You need                                                                                                                                                                         |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Play                  | macOS 13 or newer (Apple silicon) or macOS 11 or newer (Intel); Windows 10 or 11 (64-bit); or 64-bit Linux. Keyboard, or any gamepad your system recognizes.                     |
| Play online           | A second player with the **same version** of the game, and a network path between you (same Wi-Fi, a VPN like Tailscale, or a forwarded port).                                   |
| Make your own fighter | [Blender](https://www.blender.org/download/) 4.2 or newer and an AI coding agent that runs in a terminal, such as [Claude Code](https://docs.anthropic.com/en/docs/claude-code). |

You can play right away; Blender and the agent are only needed when you [make a fighter](./custom-characters).

## Install with the itch app

1. Install the free [itch app](https://itch.io/app) and sign in (or create a free itch.io account).
2. Open [Street fAIghter on itch.io](https://dustinmichels.itch.io/street-faighter), or search for it in the app.
3. Click **Install**, then **Launch**.

The app downloads new versions on its own. If macOS or Windows still shows a security warning on the first launch, follow the matching steps below.

## Install from GitHub

Open the [latest release](https://github.com/dustinmichels/street-faighter/releases/latest) and download the `.zip` for your system under **Assets**.

### macOS

1. Download `street-fAIghter-macos.zip`.
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

### Windows

1. Download `street-fAIghter-windows.zip`.
2. Right-click the `.zip` and choose **Extract All…**. Extract it to a folder you'll keep, such as `Documents\street-fAIghter`.

   ::: warning Extract it before you open it
   Don't double-click the `.exe` inside the zip. Windows then runs it from a temporary folder, and the creator kits the game writes would point your AI agent at a path that no longer exists.
   :::

3. Double-click **street-fAIghter.exe**. The first time, Windows says "Windows protected your PC", because the game isn't signed. Click **More info**, then **Run anyway**. Windows remembers the choice.

   If there's no **Run anyway** button, Smart App Control is on, and it blocks every unsigned app. [Run the game from source](/dev/) instead.

When you first host an online match, Windows Defender Firewall asks whether to allow **street-fAIghter**. Allow it on private networks; otherwise your opponent can't reach you.

### Linux

1. Download `street-fAIghter-linux.zip` and unzip it to a folder you'll keep.
2. Run `./street-fAIghter.x86_64` from that folder, or double-click it in your file manager. If it won't start, make it executable first: `chmod +x street-fAIghter.x86_64`.

## First launch

1. At **PRESS START**, press any key, click, or press a gamepad button.
2. Type your name (up to 10 characters) and press <kbd>Enter</kbd>.
3. Choose **1 PLAYER VS CPU** to fight the computer, or **2 PLAYERS ONLINE** to [play a friend](./online).

The moves and controls are on [How to play](./playing). In a match, <kbd>Esc</kbd> shows the controls (and pauses a fight against the CPU) until the knockout, then goes back to the menu.

## Updating

With the itch app, updates install on their own. Otherwise, download the new release and replace the app (or, on Windows and Linux, all the files in the game's folder). Your name, settings, and imported fighters are stored outside the game and carry over.

Online matches need both players on the same version: the game checks during the handshake and refuses a mismatch, with a message saying which versions met. The version is in the bottom-left corner of the title screen.

## Where your files are

| What                                                 | macOS                                                               | Windows                                         | Linux                                                |
| ---------------------------------------------------- | ------------------------------------------------------------------- | ----------------------------------------------- | ---------------------------------------------------- |
| Settings, imported fighters, fighters from opponents | `~/Library/Application Support/Godot/app_userdata/street-faighter/` | `%APPDATA%\Godot\app_userdata\street-faighter\` | `~/.local/share/godot/app_userdata/street-faighter/` |
| Creator kits (one folder per fighter you design)     | `~/Documents/street-fAIghter characters/`                           | `Documents\street-fAIghter characters\`         | `~/Documents/street-fAIghter characters/`            |

You can change the creator kit folder in the game. To uninstall, delete the game (or uninstall it in the itch app) and those two folders.
