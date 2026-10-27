# Online multiplayer

Two players connect directly, peer to peer. One **hosts** (red fighter, left side) and the other **joins** (blue fighter, right side). There are no accounts and no servers: the joiner needs the host's IP address.

Both players need the **same version** of the game. The version is in the bottom-left corner of the title screen.

## Host a match

1. Choose **2 PLAYERS ONLINE**.
2. Leave the port empty to use **7777**, or type another UDP port.
3. Choose **HOST**. The menu shows _Hosting on port 7777, waiting for an opponent..._ and, in place of the join row, the addresses your opponent can join with:
   - **LAN**: your local IP, for an opponent on the same network.
   - **VPN**: your Tailscale IP (`100.x.x.x`), if you run Tailscale.
   - **INTERNET**: your public IP, looked up from [ipify](https://www.ipify.org/). It only works if your router forwards the port (see [Port forwarding](#port-forwarding)). If the lookup fails, this row doesn't appear.

   Addresses include the port when it isn't 7777. Below them, a line says whether your router agreed to forward the port automatically (see [Port forwarding](#port-forwarding)).

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
| Anywhere, no VPN            | The host's router forwards a port (below), and the host shares the **INTERNET** address.                                                                                                                                         |

### Port forwarding

Only the **host** needs a forwarded port; the joiner needs nothing.

**Automatic (UPnP).** When you choose **HOST**, the game asks your router to forward the port to your computer, using UPnP; the answer takes a few seconds. The game removes the forwarding when you stop hosting or quit, and asks the router to expire it after 4 hours in case the game crashes. The line under the addresses shows the answer:

| Line                                           | What it means                                                                                                                                                                   |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| _Your router forwards UDP port 7777_           | Done. Allow the game through your [firewall](#firewall) and share the **INTERNET** address.                                                                                     |
| _No UPnP router found_                         | UPnP is off or unsupported. Turn it on in the router's settings, or forward the port by hand (below).                                                                           |
| _Your router refused to forward UDP port 7777_ | Usually the port is already forwarded to another computer. Pick another port, or change the rule by hand.                                                                       |
| _Your router isn't directly on the internet_   | Your provider shares one internet address between customers (CGNAT), or another router sits in front of yours. Forwarding can't fix that: use a [VPN](#which-address-to-share). |

**By hand.**

1. Find the host computer's local IP: the **LAN** address shown while hosting.
2. In the router's settings, forward **UDP** port **7777** (or your custom port) to that local IP. TCP forwarding won't work: the game uses UDP.
3. Allow the game through the host's [firewall](#firewall).
4. Give the joiner the **INTERNET** address.

### Firewall

The host's firewall must let the game receive UDP on its port, whichever address the joiner uses (**LAN**, **VPN**, or **INTERNET**). The joiner needs nothing.

- **Windows**: allow street-faighter when Windows asks. If the prompt was dismissed, or the joiner still gets _Could not connect to the host_, open PowerShell as administrator on the host and run:

  ```powershell
  New-NetFirewallRule -DisplayName "street-fAIghter" -Direction Inbound -Protocol UDP -LocalPort 7777 -Action Allow
  ```

  Use your port in place of `7777` if you host on another one. The rule applies on every network type, including networks Windows marks as Public. To remove it: `Remove-NetFirewallRule -DisplayName "street-fAIghter"`.

- **macOS**: click **Allow** when asked, or check **System Settings → Network → Firewall → Options**.

## Connection quality

Each side's inputs take effect 3 frames (50 ms) after you press them, which gives them time to reach the other machine. When the opponent's input for a frame still hasn't arrived, the game guesses that they kept doing what they did last and plays on. Once the real input arrives, it checks the guess; if it was wrong, it rewinds up to 5 frames and replays them with the real input (rollback). A fighter may then jump a short distance on your screen. The game only stops to wait when an input is more than 8 frames (133 ms) late, around 250 ms ping.

In tests with simulated latency, a match at about 80 ms ping never waited, and one at about 150 ms ping waited on 2 frames in 20 seconds.

The bottom-left corner shows the ping and the input delay during a match. <kbd>F3</kbd> opens a network overlay with rollbacks, stalled frames, and packet loss.

## When a match ends early

The match freezes, shows the reason, and returns to the menu after a few seconds when:

- the opponent quits (_Opponent disconnected_),
- nothing arrives from them for 5 seconds (_Connection lost_), or
- the two games compute different results (_Desync_). This shouldn't happen; if it does, please [open an issue](https://github.com/dustinmichels/street-faighter/issues).

Problems connecting in the first place are covered in [Troubleshooting](./troubleshooting#online).
