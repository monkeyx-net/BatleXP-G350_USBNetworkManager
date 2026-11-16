# USB Network Manager (Battle XP G350 / RK3326)

Two scripts that switch the USB-C port between **network** and **charge-only**.

| Script | What it does |
|---|---|
| `USB_Mode.sh` | Toggles between network and charge. Args: `net`, `charge`, `status` |
| `USB_Gadget_Setup.sh` | Run once: switches the port to device mode, then reboots. `restore` undoes it |

Written for ArkOS / dArkOS, ROCKNIX / JELOS, Knulli / Batocera, AmberELEC and muOS. The scripts run as root
or through `sudo`, find the boot partition themselves, and depend on no firmware-specific helpers.

## Install

Copy both `.sh` files to the firmware's Ports or Tools folder:

| Firmware | Folder |
|---|---|
| ArkOS / dArkOS | `/roms/tools/` or `/roms/ports/` |
| ROCKNIX / JELOS / AmberELEC | `/storage/roms/ports/` |
| Knulli / Batocera | `/userdata/roms/ports/` |
| muOS | `/mnt/mmc/MUOS/application/` |

Refresh the game list, then:

1. Run **USB_Gadget_Setup** once. The console reboots.
2. Run **USB_Mode** to turn networking on. Run it again to go back to charge-only.

## Network

The console gives itself three fixed addresses and uses whichever PC address answers first. It sets
its default route and DNS through that address.

| PC setup | PC address | Console address |
|---|---|---|
| Windows Internet Connection Sharing (ICS) | `192.168.137.1` | `192.168.137.2` |
| Linux NetworkManager "Shared to other computers" (default) | `10.42.0.1` | `10.42.0.2` |
| Direct link, or Linux shared with a custom address | `192.168.7.1` | `192.168.7.2` |

Charge mode removes the USB gadget and restores the original DNS. No reboot is needed.

SSH, Samba and other services are left to the firmware's own settings. Connect to whichever console
address matches your setup, for example `ssh root@192.168.7.2`.

### Windows

- **Direct link:** set the new USB adapter to `192.168.7.1 / 255.255.255.0`.
- **Internet through the PC:** open the adapter that has internet, go to Properties > Sharing, and share
  it with the new USB adapter.

## Linux PC

Plug the console in and run **USB_Mode**. The PC sees a new wired adapter. Its name is usually
`enx02…` (based on the console's fixed MAC address) or `usb0`. To find it:

```sh
ip -br link | grep -E 'enx02|usb0'
nmcli device                       # shows it as "ethernet", often "connecting" or "disconnected"
```

The MAC address is derived from the console's serial number, so the name and any saved profile stay the
same on every connection. Below, `<usb-if>` means that name.

Choose **one** method for the adapter:

- **Manual, `192.168.7.1/24`, no gateway:** a direct link with no internet for the console.
- **Shared to other computers:** the PC routes the console to the internet. NetworkManager handles
  NAT, IP forwarding and DHCP itself.

Each desktop below shows how to set either one.

### GNOME (Ubuntu, Fedora Workstation, Pop!_OS…)

1. Open Settings > Network. The console appears under **USB Ethernet** (or a second **Wired** entry).
2. Click the gear icon, then open the **IPv4** tab.
   - Direct link: choose **Manual**, address `192.168.7.1`, netmask `255.255.255.0`, gateway empty.
   - Internet sharing: choose **Shared to other computers**.
3. In the **IPv6** tab choose **Disable**. Click **Apply**, then switch the connection off and on.

### KDE Plasma (Kubuntu, KDE neon, Fedora KDE…)

1. Open System Settings > Wi-Fi & Networking (or *Connections*), then select the new wired connection.
   If there is none, click **+** and add a **Wired Ethernet** connection.
2. On the **Wired** tab, set *Restrict to device* to `<usb-if>` so the profile can't take over your real
   Ethernet port.
3. Open the **IPv4** tab.
   - Direct link: choose **Manual**, then click **Add** and enter `192.168.7.1`, netmask
     `255.255.255.0`, gateway empty.
   - Internet sharing: choose **Shared to other computers**.
4. In the **IPv6** tab choose **Disabled**. Click **Apply**, then connect from the network tray icon.

### XFCE / MATE / Cinnamon / LXQt (Xubuntu, Mint…)

These use the NetworkManager applet (`nm-applet`).

1. Right-click the network tray icon and choose **Edit Connections…**. You can also run
   `nm-connection-editor`.
2. Select the new wired connection, or click **+** and add an **Ethernet** connection.
3. On the **Ethernet** tab, set *Device* to `<usb-if>`.
4. Open **IPv4 Settings**.
   - Direct link: set *Method* to **Manual**, then click **Add** and enter `192.168.7.1`, `24`,
     gateway empty.
   - Internet sharing: set *Method* to **Shared to other computers**.
5. Set **IPv6 Settings** to **Disable**. Save, then reconnect from the tray icon.

### Any desktop, from the terminal (nmcli)

```sh
# Direct link
nmcli con add type ethernet ifname <usb-if> con-name console-usb \
      ipv4.method manual ipv4.addresses 192.168.7.1/24 ipv6.method disabled

# OR internet sharing (pinning the address to 192.168.7.1 is optional; leaving it out gives 10.42.0.1)
nmcli con add type ethernet ifname <usb-if> con-name console-usb \
      ipv4.method shared ipv4.addresses 192.168.7.1/24 ipv6.method disabled

nmcli con up console-usb
```

To switch between methods later, run `nmcli con modify console-usb ipv4.method …`. To start over, run
`nmcli con delete console-usb`.

Without NetworkManager (systemd-networkd, or a plain shell), a direct link is just:

```sh
sudo ip addr add 192.168.7.1/24 dev <usb-if> && sudo ip link set <usb-if> up
```

### Firewall

A **direct link** usually needs no changes, because the PC starts the SSH, SFTP or Samba connection to the
console and the firewall lets the replies back in. You only need a rule if the console must reach a
service on the PC. In that case, trust the interface.

**Internet sharing** also needs traffic *forwarded* from `<usb-if>` to your internet interface (`<wan-if>`,
e.g. `wlp2s0` or `enp3s0`). NetworkManager adds the NAT rules, but a firewall that drops forwarded
traffic will still block them.

**ufw** (Ubuntu, Mint, Kubuntu, Xubuntu). Its default forward policy is DROP.

```sh
sudo ufw allow in on <usb-if>                          # console -> PC (DNS, DHCP, any PC service)
sudo ufw route allow in on <usb-if> out on <wan-if>    # sharing only: console -> internet
```

**firewalld** (Fedora, openSUSE, RHEL-likes)

```sh
# Sharing: recent NetworkManager puts shared connections in the "nm-shared" zone, which already
# allows the needed traffic. Check with:
firewall-cmd --get-active-zones

# Direct link (or if the interface ended up in a restrictive zone): trust it
nmcli con modify console-usb connection.zone trusted && nmcli con up console-usb
# or: sudo firewall-cmd --permanent --zone=trusted --add-interface=<usb-if> && sudo firewall-cmd --reload
```

**nftables** (only if you run your own ruleset; NetworkManager adds its own NAT rules for sharing). Adjust
`inet filter`, `input` and `forward` to match your table and chain names:

```sh
sudo nft add rule inet filter input   iifname "<usb-if>" accept
sudo nft add rule inet filter forward iifname "<usb-if>" oifname "<wan-if>" accept
sudo nft add rule inet filter forward iifname "<wan-if>" oifname "<usb-if>" ct state established,related accept
```

**iptables** (legacy)

```sh
sudo iptables -I INPUT   -i <usb-if> -j ACCEPT
sudo iptables -I FORWARD -i <usb-if> -o <wan-if> -j ACCEPT
sudo iptables -I FORWARD -i <wan-if> -o <usb-if> -m state --state ESTABLISHED,RELATED -j ACCEPT
# Without NetworkManager sharing you must also do NAT and forwarding yourself:
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 192.168.7.0/24 -o <wan-if> -j MASQUERADE
```

To make nftables or iptables rules permanent, save them the way your distro does it
(`/etc/nftables.conf`, `iptables-save`, `netfilter-persistent save`).

### Linux troubleshooting

- **No new adapter appears:** run `dmesg -w` on the PC and plug the console in again. You should see a
  `cdc_ether` or `rndis_host` line. If nothing appears, check that you're using a data cable (some
  cables only charge) and that **USB_Mode** reports NETWORK on.
- **Adapter stays "connecting":** NetworkManager is trying DHCP on it. Create the profile described above.
- **Console says "PC not answering":** run `ping 192.168.7.2` (or `10.42.0.2`) from the PC. If that works
  but the console still can't get out, the cause is forwarding or the firewall (see above).
- **Internet works by IP but not by name:** the console uses the PC (dnsmasq) for DNS, then `1.1.1.1`.
  Allow DNS (port 53) on `<usb-if>`, or use `ufw allow in on <usb-if>`.

## Notes

- The gadget is `g_ether` when the kernel has it, otherwise an RNDIS gadget over configfs.
  The configfs fallback works with Windows and Linux. macOS needs `g_ether`.
- If the firmware has its own USB/MTP gadget mode enabled, turn it off first.
- `USB_Gadget_Setup.sh` patches only DTBs whose `model` matches the running console. It keeps a
  `*.usbnet-orig` backup next to each patched file. In device mode, OTG pendrives don't work;
  `USB_Gadget_Setup.sh restore` brings them back.
