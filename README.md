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

The console takes `192.168.7.2` and `192.168.137.2`. It uses whichever PC address answers:

- **Direct link:** set the PC's new USB adapter to `192.168.7.1 / 255.255.255.0`.
- **Internet through the PC (Windows ICS):** share your internet connection with the new
  adapter. Windows gives it `192.168.137.1`, and the console then routes and resolves DNS through it.

Charge mode removes the USB gadget and restores the original DNS. No reboot is needed.

SSH, Samba and other services are left to the firmware's own settings.

## Notes

- The gadget is `g_ether` when the kernel has it, otherwise an RNDIS gadget over configfs.
  The configfs fallback works with Windows and Linux. macOS needs `g_ether`.
- If the firmware has its own USB/MTP gadget mode enabled, turn it off first.
- `USB_Gadget_Setup.sh` patches only DTBs whose `model` matches the running console. It keeps a
  `*.usbnet-orig` backup next to each patched file. In device mode, OTG pendrives don't work;
  `USB_Gadget_Setup.sh restore` brings them back.
