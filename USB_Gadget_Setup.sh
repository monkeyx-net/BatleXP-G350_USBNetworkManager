#!/bin/bash
# USB_Gadget_Setup.sh - one-time: put the USB-C port in device (peripheral)
# mode so USB_Mode.sh can bring up USB networking. Reboots when done.
#
#   (no args)  enable device mode (backs up each DTB as *.usbnet-orig)
#   restore    put the original DTB(s) back (USB host / OTG pendrives again)
#
# Finds the boot partition and DTB for ArkOS/dArkOS (/boot), ROCKNIX/JELOS
# and AmberELEC (/flash), Knulli/Batocera (/boot) and muOS (/mnt/boot).
# Only DTBs whose model matches this console are touched.

export PATH="/usr/sbin:/sbin:/usr/bin:/bin:$PATH"
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

if [ -z "$SSH_CONNECTION" ] && [ ! -t 1 ] && [ -e /dev/tty1 ]; then
    $SUDO chmod 666 /dev/tty1 2>/dev/null
    [ -w /dev/tty1 ] && exec >/dev/tty1 2>&1
fi

say() { echo "[usbsetup] $*"; }
finish() { [ -z "$SSH_CONNECTION" ] && [ ! -t 0 ] && sleep 4; exit "$1"; }

MODE="${1:-enable}"
MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
[ -n "$MODEL" ] || { say "Cannot read the device model."; finish 1; }
command -v python3 >/dev/null || { say "python3 not found."; finish 1; }

# Collect DTBs on the boot partition(s)
DTBS=""
for d in /boot /flash /mnt/boot; do
    [ -d "$d" ] || continue
    DTBS="$DTBS $(find "$d" -maxdepth 3 -name '*.dtb' 2>/dev/null | tr '\n' ' ')"
done
[ -n "${DTBS// /}" ] || { say "No DTB files found on the boot partition."; finish 1; }

# Make the boot partition(s) writable for the duration of the change
REMOUNT=""
for f in $DTBS; do
    mp=$(df -P "$f" 2>/dev/null | awk 'NR==2{print $6}')
    case " $REMOUNT " in *" $mp "*) continue ;; esac
    if awk -v m="$mp" '$2==m && $4 ~ /(^|,)ro(,|$)/ {f=1} END{exit !f}' /proc/mounts; then
        $SUDO mount -o remount,rw "$mp" && REMOUNT="$REMOUNT $mp"
    fi
done

# shellcheck disable=SC2086
$SUDO python3 - "$MODE" "$MODEL" $DTBS <<'PY'
import os, shutil, struct, sys

mode, model, files = sys.argv[1], sys.argv[2], sys.argv[3:]

class Node:
    def __init__(s, name): s.name, s.props, s.kids = name, {}, []

def parse(d):
    (magic, _, o_st, o_str, o_rsv, ver, _, cpu, _, sz_st) = struct.unpack('>10I', d[:40])
    if magic != 0xd00dfeed: raise ValueError('not a dtb')
    def s(o): e = d.index(b'\0', o_str + o); return d[o_str + o:e].decode()
    p, stack, root = o_st, [], None
    while p < o_st + sz_st:
        t = struct.unpack('>I', d[p:p+4])[0]; p += 4
        if t == 1:
            e = d.index(b'\0', p); n = Node(d[p:e].decode()); p = (e + 4) & ~3
            (stack[-1].kids.append(n) if stack else None); root = root or n; stack.append(n)
        elif t == 2: stack.pop()
        elif t == 3:
            ln, no = struct.unpack('>II', d[p:p+8]); p += 8
            stack[-1].props[s(no)] = d[p:p+ln]; p = (p + ln + 3) & ~3
        elif t == 9: break
    return root, d[o_rsv:o_st], cpu

def build(root, rsv, cpu):
    st, strs, idx = bytearray(), bytearray(), {}
    pad = lambda b: b.extend(b'\0' * (-len(b) % 4))
    def w(n):
        st.extend(struct.pack('>I', 1) + n.name.encode() + b'\0'); pad(st)
        for k, v in n.props.items():
            if k not in idx: idx[k] = len(strs); strs.extend(k.encode() + b'\0')
            st.extend(struct.pack('>III', 3, len(v), idx[k]) + v); pad(st)
        for c in n.kids: w(c)
        st.extend(struct.pack('>I', 2))
    w(root); st.extend(struct.pack('>I', 9))
    o_rsv = 40; o_st = o_rsv + len(rsv); o_str = o_st + len(st)
    hdr = struct.pack('>10I', 0xd00dfeed, o_str + len(strs), o_st, o_str, o_rsv,
                      17, 16, cpu, len(strs), len(st))
    return hdr + rsv + bytes(st) + bytes(strs)

def walk(n):
    yield n
    for c in n.kids: yield from walk(c)

done = 0
for f in files:
    bak = f + '.usbnet-orig'
    try: d = open(f, 'rb').read(); root, rsv, cpu = parse(d)
    except Exception: continue
    if model and root.props.get('model', b'').rstrip(b'\0').decode(errors='ignore') != model:
        continue
    if mode == 'restore':
        if os.path.exists(bak):
            shutil.copyfile(bak, f); os.remove(bak); print('restored', f); done += 1
        continue
    changed = False
    for n in walk(root):
        if n.name.startswith('usb@') and b'dwc2' in n.props.get('compatible', b'') \
                and 'dr_mode' in n.props and n.props['dr_mode'] != b'peripheral\0':
            n.props['dr_mode'] = b'peripheral\0'; changed = True
        if n.name == 'otg-port' and n.props.get('status') != b'okay\0':
            n.props['status'] = b'okay\0'; changed = True
    if not changed:
        print('already in device mode', f); continue
    if not os.path.exists(bak): shutil.copyfile(f, bak)
    open(f, 'wb').write(build(root, rsv, cpu)); print('patched', f); done += 1
sys.exit(0 if done else 3)
PY
rc=$?
sync
for mp in $REMOUNT; do $SUDO mount -o remount,ro "$mp" 2>/dev/null; done

case $rc in
    0) say "Done. Rebooting in 3s..."; sleep 3; $SUDO reboot ;;
    3) say "Nothing changed (no matching DTB or already set)." ; finish 0 ;;
    *) say "Failed (python exit $rc)."; finish 1 ;;
esac
