# Online multiplayer

Two players connect directly, peer to peer. One **hosts** (red fighter, left side) and the other **joins** (blue fighter, right side). There are no accounts and no servers: the joiner needs the host's IP address.

Both players need the **same version** of the game. The version is in the bottom-left corner of the title screen.

## Host a match

1. Choose **2 PLAYERS ONLINE**.
2. Leave the port empty to use **7777**, or type another UDP port.
3. Choose **HOST**. The menu shows _Hosting on port 7777, waiting for an opponent..._ and, in place of the join row, the addresses your opponent can join with:
   - **LAN**: your local IP, for an opponent on the same network.
   - **VPN**: your Tailscale IP (`100.x.x.x`), if you run Tailscale.
   - **INTERNET**: your public IP, looked up from [ipify](https://www.ipify.org/). It only works if you forward the port (see [Port forwarding](#port-forwarding)). If the lookup fails, this row doesn't appear.

   Addresses include the port when it isn't 7777.

4. Choose **COPY** next to the right address (see [Which address to share](#which-address-to-share)) and send it to the other player.

## Join a match

1. Choose **2 PLAYERS ONLINE**.
2. Type the host's address in **HOST IP OR IP:PORT**: `192.168.1.50`, `203.0.113.19:8000` for a port other than 7777, or `[2001:db8::5]:7777` for IPv6.
3. Choose **JOIN**.

Once both games have loaded, a shared **3, 2, 1, FIGHT!** starts the match on both screens at the same moment.

## Custom fighters online

Pick your fighter first (**1 PLAYER VS CPU** or **CHARACTERS**); online you play the fighter you last chose. When the match starts, each game sends its fighter to the other one if the other doesn't have it yet. The receiving game checks the file with the same validator as an import, keeps a copy for next time, and waits up to 10 seconds for it. If the transfer fails, that fighter shows up as the default model and the match goes ahead: models never change how a fight plays out.

Don't want to see other people's models? Toggle **OPPONENTS: AS CHOSEN** to **OPPONENTS: DEFAULT** on the online screen. Their fighters are then neither downloaded nor shown.

## Rematch

After a knockout, both players press <kbd>R</kbd> to agree to a rematch on the same connection. The HUD shows whether you're waiting for your opponent or they're waiting for you. Before the KO, <kbd>R</kbd> does nothing online, and <kbd>Esc</kbd> shows the controls without pausing: the fight goes on. Pressing <kbd>Esc</kbd> after the KO leaves the match and returns to the menu; your opponent sees _Opponent disconnected_.

## Which address to share

| Where the other player is   | What to do                                                                                                                                                                                                                       |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Same Wi-Fi or wired network | Share the **LAN** address. No router setup needed.                                                                                                                                                                               |
| Anywhere, easiest           | Both install a free mesh VPN such as [Tailscale](https://tailscale.com/) or [ZeroTier](https://www.zerotier.com/) and join the same network. Share the **VPN** address (ZeroTier addresses show up as **LAN**). No router setup. |
| Anywhere, no VPN            | The host forwards a port on their router (below) and shares the **INTERNET** address.                                                                                                                                            |

### Port forwarding

Only the **host** forwards a port; the joiner needs nothing.

1. Find the host computer's local IP: the **LAN** address shown while hosting.
2. In the router's settings, forward **UDP** port **7777** (or your custom port) to that local IP. TCP forwarding won't work: the game uses UDP.
3. If a firewall is on, allow incoming connections for **street-faighter**. On macOS, click **Allow** when asked, or check **System Settings → Network → Firewall → Options**.
4. Give the joiner the **INTERNET** address.

## Connection quality

The game runs in lockstep: each side waits for the other's input before simulating a frame, with 3 frames (50 ms) of input delay to hide the wait. On a LAN it plays at full speed. At around 70 ms ping with some jitter, it stalls on about one frame in five; at around 150 ms ping, it runs at about half speed.

The bottom-left corner shows the ping and the input delay during a match. <kbd>F3</kbd> opens a network overlay with stalled frames and packet loss.

## When a match ends early

The match freezes, shows the reason, and returns to the menu after a few seconds when:

- the opponent quits (_Opponent disconnected_),
- nothing arrives from them for 5 seconds (_Connection lost_), or
- the two games compute different results (_Desync_). This shouldn't happen; if it does, please [open an issue](https://github.com/dustinmichels/street-faighter/issues).

Problems connecting in the first place are covered in [Troubleshooting](./troubleshooting#online).
