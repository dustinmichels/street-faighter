# TODO — Internet play: get the INTERNET address working

Goal: two players on different networks connect by direct IP (the **INTERNET** row on the host screen), without a VPN.

## Current state (2026-10-28)

- **LAN works:** two Macs on the same Wi-Fi connected with the host's **LAN** address. So the game, the port and the host's macOS firewall are fine.
- **INTERNET fails:** joining the host's **INTERNET** address did not connect, and the host screen said _"No UPnP router found"_.
- **Host network** (checked from the host Mac):

  | Check                                   | Result                                                                                     | Meaning                                                                                                   |
  | --------------------------------------- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
  | Default gateway                         | `10.0.0.1`, admin page titled `XFINITY`                                                    | Comcast Xfinity gateway                                                                                   |
  | Public IP (ipify)                       | a Comcast `73.x` address                                                                   |                                                                                                           |
  | `traceroute 1.1.1.1`                    | hop 1 `10.0.0.1`, hop 2 already a public Comcast address (`96.120.x`)                      | One NAT, **no CGNAT**, no second router. Port forwarding can work.                                        |
  | SSDP `M-SEARCH ssdp:all`, 3 s           | only `10.0.0.135` answered (a media renderer: AVTransport, RenderingControl); not the gateway | UPnP is **off** on the gateway. This is why `PortMapper` reports `NO_ROUTER`.                             |
  | NAT-PMP (UDP `10.0.0.1:5351`)           | no reply                                                                                   | NAT-PMP isn't available either, so adding NAT-PMP/PCP to `PortMapper` wouldn't help on this router.       |

- **Why the INTERNET test failed:** two separate reasons, either of which is enough.
  1. Nothing forwards UDP 7777 to the host: UPnP is off and there is no manual rule.
  2. The joiner was on the **same Wi-Fi**. Joining your own public IP from inside the network needs the router to support NAT loopback (hairpinning). Many consumer routers don't; whether this Xfinity gateway does is unverified. So the INTERNET address can't be tested from the same Wi-Fi, even once forwarding works.

## 1. Make this network reachable (no code)

- [ ] **Turn on UPnP**: `http://10.0.0.1` only shows "please download the Xfinity app" until the admin tool is enabled: Xfinity app → **WiFi → View WiFi equipment → Advanced settings → Admin Tool online access**, toggle on, set a password, **Save** ([Xfinity: Admin Tool access](https://www.xfinity.com/support/articles/admin-tool-access)). Then log in at `http://10.0.0.1` (user `admin`), **Advanced → Device Discovery**, enable UPnP ([Xfinity: Configure device discovery](https://www.xfinity.com/support/articles/configure-device-discovery-for-wifi)). Xfinity recommends turning admin access off again afterwards. Then HOST again; the line should say _"Your router forwards UDP port 7777"_. Xfinity users report UPnP sometimes turning itself off again (e.g. after a gateway reboot), so check the line each time.
- [ ] **Or forward the port by hand**: on xFi gateways port forwarding moved from `10.0.0.1` to the Xfinity app: **WiFi → View WiFi equipment → Advanced Settings → Port forwarding → Add Port Forward**, pick the host Mac, **Manual Setup**, UDP 7777 ([Xfinity: Port forwarding in the app](https://www.xfinity.com/support/articles/xfi-port-forwarding)). The rule is tied to the device you pick (IPv4 + DHCP only). Xfinity says rules may break with MAC randomization, so set the Mac's **Private Wi-Fi Address** for this network to **Off** or **Fixed** (System Settings → Wi-Fi → Details), not **Rotating**, before adding the rule. Whether the gateway also pins the device's IP is unverified: if the forward stops working, compare `ipconfig getifaddr en0` with the address in the rule.
- [ ] **Xfinity Advanced Security**: per the same article, if it detects a known threat aimed at a forwarded or UPnP-opened port, it blocks all traffic from that port to the device. **Home → Advanced Security → Allow access** whitelists one source IP for 30 days (e.g. the brother's). Only relevant if the forward is set up and connections still fail.
- [ ] **Test from outside the network**: put the joining Mac on a phone hotspot (Wi-Fi off), not the home Wi-Fi, then JOIN the INTERNET address. This avoids the hairpinning question.
- [ ] Then the real test: brother on Windows joins the INTERNET address. He needs no forwarding or firewall rule as the joiner (outbound UDP).
- [ ] Fallback that needs no router changes: Tailscale on both machines, join the **VPN** address.

## 2. Game changes that would have made this obvious

- [ ] **Same-network hint on JOIN**: the joiner looks up its own public IP (`PUBLIC_IP_URL`, already used by the host screen). If the typed address equals it, the opponent is on the same network: show "THAT'S YOUR OWN NETWORK'S INTERNET ADDRESS. USE THE HOST'S LAN ADDRESS." instead of a long ENet timeout.
- [ ] **Join failure text**: when a join times out, say what's most likely: the host's port isn't forwarded (check the line under the host's addresses), or the host's firewall blocks it. Today the failure doesn't mention forwarding.
- [ ] **Host screen**: when the forward result is `NO_ROUTER` or `REFUSED`, dim the INTERNET row or label it "NEEDS PORT FORWARD", so it isn't shared as if it works. Keep it copyable: a manual forward also reports `NO_ROUTER`.
- [ ] **Hint text for `NO_ROUTER`**: add "TURN ON UPNP IN YOUR ROUTER" to `"NO UPNP ROUTER FOUND. FOR INTERNET, FORWARD UDP PORT %d YOURSELF."` (`menu/menu.gd`), and add the Xfinity steps above to `docs/guide/online.md` → Port forwarding, since Xfinity is common and hides both settings.

## 3. Bigger options (no router setup at all)

- [ ] **Reachability self-test**: after HOST, an outside server tries to reach `public_ip:port` and the host screen shows "REACHABLE FROM THE INTERNET" or not. A raw UDP probe gets no answer from an ENet socket, so the server must speak ENet (headless Godot export) or the game must answer a small probe packet on the same port. Needs hosted infrastructure; shares it with `lobby.md`.
- [ ] **Relay / NAT traversal**: WebRTC with STUN and a TURN fallback, or a relay server, connects players whose routers can't forward. Planned as tier 3 in `lobby.md` §1 and §4; the same work fixes this case.
