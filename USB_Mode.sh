#!/bin/bash
# USB_Mode.sh - switch the USB-C port between NETWORK and CHARGE.
#
#   (no args)  toggle: network -> charge, charge -> network
#   net        USB network on (console 192.168.7.2 / 192.168.137.2)
#   charge     USB network off; the port only charges
#   status     print the current state
#
# Works on ArkOS/dArkOS, ROCKNIX/JELOS, Knulli/Batocera, AmberELEC and muOS.
# Needs USB device mode enabled; run USB_Gadget_Setup.sh once if it says so.

export PATH="/usr/sbin:/sbin:/usr/bin:/bin:$PATH"
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# Launched from EmulationStation on a console TTY (ArkOS-style): show output.
if [ -z "$SSH_CONNECTION" ] && [ ! -t 1 ] && [ -e /dev/tty1 ]; then
    $SUDO chmod 666 /dev/tty1 2>/dev/null
    [ -w /dev/tty1 ] && exec >/dev/tty1 2>&1
fi

G=/sys/kernel/config/usb_gadget/usbnet
STATE=/tmp/usbnet
NETS="192.168.137 192.168.7"   # Windows ICS first, then direct link

say() { echo "[usbnet] $*"; }

iface() {
    if [ -f "$G/functions/rndis.usb0/ifname" ]; then
        cat "$G/functions/rndis.usb0/ifname"
    elif [ -d /sys/class/net/usb0 ]; then
        echo usb0
    fi
}

is_up() { local i; i=$(iface); [ -n "$i" ] && ip -4 addr show dev "$i" 2>/dev/null | grep -q 'inet '; }

serial() {
    local s
    s=$(tr -d '\0' < /proc/device-tree/serial-number 2>/dev/null)
    [ -z "$s" ] && s=$(awk '/^Serial/{print $3}' /proc/cpuinfo 2>/dev/null)
    [ -z "$s" ] && s=$(head -c 16 /etc/machine-id 2>/dev/null)
    printf '%s' "${s:-0000000000000000}"
}

gadget_up() {
    [ -n "$(iface)" ] && return 0

    if [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; then
        say "No USB device controller: the port is in host mode."
        say "Run USB_Gadget_Setup.sh once, then reboot."
        return 1
    fi

    local s hex mac_dev mac_host
    s=$(serial)
    hex=$(printf '%s' "$s" | tr -cd '0-9a-fA-F' | tr 'A-F' 'a-f' | head -c 6)
    hex=$(printf '%-6s' "$hex" | tr ' ' '0')
    mac_dev="02:${hex:0:2}:${hex:2:2}:${hex:4:2}:00:01"
    mac_host="02:${hex:0:2}:${hex:2:2}:${hex:4:2}:00:02"

    # 1) Legacy g_ether (proven on ArkOS/dArkOS, handles Windows+mac+Linux)
    if $SUDO modprobe g_ether iSerialNumber="$s" dev_addr="$mac_dev" host_addr="$mac_host" 2>/dev/null \
        || $SUDO modprobe g_ether 2>/dev/null; then
        for _ in 1 2 3 4 5 6 7 8 9 10; do [ -n "$(iface)" ] && return 0; sleep 0.3; done
    fi

    # 2) configfs RNDIS gadget (kernels without g_ether)
    $SUDO modprobe libcomposite 2>/dev/null
    grep -q ' /sys/kernel/config ' /proc/mounts || $SUDO mount -t configfs none /sys/kernel/config 2>/dev/null
    [ -d /sys/kernel/config/usb_gadget ] || { say "No USB gadget support in this kernel."; return 1; }

    local udc
    udc=$(ls /sys/class/udc | head -n1)
    $SUDO sh -e -c "
        mkdir -p $G && cd $G
        echo 0x1d6b > idVendor; echo 0x0104 > idProduct
        echo 0x0100 > bcdDevice; echo 0x0200 > bcdUSB
        echo 0xEF > bDeviceClass; echo 0x02 > bDeviceSubClass; echo 0x01 > bDeviceProtocol
        mkdir -p strings/0x409 configs/c.1/strings/0x409 functions/rndis.usb0
        echo '$s' > strings/0x409/serialnumber
        echo 'Handheld' > strings/0x409/manufacturer
        echo 'USB Network' > strings/0x409/product
        echo 'RNDIS' > configs/c.1/strings/0x409/configuration
        echo 250 > configs/c.1/MaxPower
        echo $mac_dev > functions/rndis.usb0/dev_addr
        echo $mac_host > functions/rndis.usb0/host_addr
        if [ -d os_desc ]; then
            echo 1 > os_desc/use; echo 0xcd > os_desc/b_vendor_code; echo MSFT100 > os_desc/qw_sign
            echo RNDIS > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
            echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id
            [ -e os_desc/c.1 ] || ln -s configs/c.1 os_desc/
        fi
        [ -e configs/c.1/rndis.usb0 ] || ln -s functions/rndis.usb0 configs/c.1/
        echo $udc > UDC
    " 2>/dev/null || {
        say "Could not bind $udc. Turn off the firmware's own USB/MTP gadget mode."
        gadget_down; return 1
    }
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -n "$(iface)" ] && return 0; sleep 0.3; done
    say "Gadget created but no network interface appeared."
    return 1
}

gadget_down() {
    if [ -d "$G" ]; then
        $SUDO sh -c "
            cd $G
            echo '' > UDC
            rm -f configs/c.1/rndis.usb0 os_desc/c.1
            rmdir configs/c.1/strings/0x409 configs/c.1 functions/rndis.usb0 strings/0x409
            cd .. && rmdir usbnet
        " 2>/dev/null
    fi
    $SUDO modprobe -r g_ether 2>/dev/null
}

net_on() {
    gadget_up || return 1
    local i gw="" n
    i=$(iface)
    $SUDO ip addr flush dev "$i" 2>/dev/null
    for n in $NETS; do $SUDO ip addr add "$n.2/24" dev "$i" 2>/dev/null; done
    $SUDO ip link set "$i" up

    say "Waiting for the PC..."
    for _ in 1 2 3 4 5 6 7 8; do
        for n in $NETS; do
            ping -c1 -W1 "$n.1" >/dev/null 2>&1 && { gw="$n.1"; break 2; }
        done
    done

    if [ -n "$gw" ]; then
        $SUDO ip route replace default via "$gw" dev "$i" metric 50
        if [ ! -e "$STATE.resolv" ]; then
            cat /etc/resolv.conf > "$STATE.resolv" 2>/dev/null || : > "$STATE.resolv"
        fi
        { echo "nameserver $gw"; echo "nameserver 1.1.1.1"; echo "nameserver 8.8.8.8"; } \
            | $SUDO sh -c 'cat > /etc/resolv.conf' 2>/dev/null
        say "NETWORK on: console ${gw%.1}.2, PC $gw"
    else
        say "NETWORK on: console 192.168.7.2 (PC not answering yet;"
        say "set the PC adapter to 192.168.7.1/24 or enable ICS)"
    fi
}

charge_on() {
    local i; i=$(iface)
    if [ -n "$i" ]; then
        $SUDO ip route del default dev "$i" 2>/dev/null
        $SUDO ip addr flush dev "$i" 2>/dev/null
        $SUDO ip link set "$i" down 2>/dev/null
    fi
    gadget_down
    if [ -f "$STATE.resolv" ]; then
        $SUDO sh -c "cat '$STATE.resolv' > /etc/resolv.conf" 2>/dev/null
        rm -f "$STATE.resolv"
    fi
    say "CHARGE only: USB network off."
}

status() {
    if is_up; then
        say "NETWORK: $(iface) $(ip -4 -o addr show dev "$(iface)" | awk '{printf "%s ", $4}')"
        ip route | awk '/^default/ && /'"$(iface)"'/ {print "[usbnet] gateway " $3}'
    else
        say "CHARGE (USB network off)"
    fi
    [ -z "$(ls /sys/class/udc 2>/dev/null)" ] && say "Host mode: run USB_Gadget_Setup.sh first."
}

case "${1:-toggle}" in
    net|network|on) net_on ;;
    charge|off)     charge_on ;;
    status)         status ;;
    toggle)         if is_up; then charge_on; else net_on; fi ;;
    *) echo "usage: $0 [net|charge|status]"; exit 2 ;;
esac
rc=$?
[ -z "$SSH_CONNECTION" ] && [ ! -t 0 ] && sleep 3
exit $rc
