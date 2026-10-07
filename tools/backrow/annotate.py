#!/usr/bin/env python3
"""Disassemble a 32-bit Intel Mach-O binary and label each memory load with the
selector, class, Objective-C string or C string it points at.

i386 code is position independent: a method puts its own address in a register,
either with `call next; pop %ebx` or by calling a get-pc thunk
(`mov (%esp), %ebx; ret`), and then loads `offset(%ebx)`. otool doesn't resolve
those, so this script tracks the base address and looks each load up in the
binary's sections.

Usage, with a thin i386 copy of BackRow taken from the iMac:
    lipo -thin i386 BackRow -output BackRow.i386
    tools/backrow/annotate.py BackRow.i386 > backrow-annotated.txt
    tools/backrow/annotate.py BackRow.i386 '-[BRVideo initWithMedia:attributes:allowAllMovieTypes:error:]'
"""
import re
import struct
import subprocess
import sys

path = sys.argv[1]
symbol = sys.argv[2] if len(sys.argv) > 2 else None
data = open(path, 'rb').read()

sections = []
ncmds = struct.unpack_from('<I', data, 16)[0]
offset = 28
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', data, offset)
    if cmd == 1:  # LC_SEGMENT
        nsects = struct.unpack_from('<I', data, offset + 48)[0]
        s = offset + 56
        for _ in range(nsects):
            sect = data[s:s + 16].rstrip(b'\0').decode()
            seg = data[s + 16:s + 32].rstrip(b'\0').decode()
            addr, sz, fileoff = struct.unpack_from('<III', data, s + 32)
            sections.append((seg, sect, addr, sz, fileoff))
            s += 68
    offset += size


def locate(address):
    for seg, sect, addr, sz, fileoff in sections:
        if addr <= address < addr + sz:
            return seg, sect, fileoff + (address - addr)
    return None


def cstring(fileoff):
    return data[fileoff:data.index(b'\0', fileoff)].decode('latin1')


def describe(address):
    found = locate(address)
    if not found:
        return None
    seg, sect, fileoff = found
    if sect in ('__cstring', '__meth_var_names', '__class_names'):
        return f'"{cstring(fileoff)}"'
    if sect in ('__message_refs', '__cls_refs'):
        target = locate(struct.unpack_from('<I', data, fileoff)[0])
        return f"{sect.strip('_')} {cstring(target[2])}" if target else None
    if sect == '__cfstring':
        target = locate(struct.unpack_from('<I', data, fileoff + 8)[0])
        return f'@"{cstring(target[2])}"' if target else None
    if sect == '__protocol':
        target = locate(struct.unpack_from('<I', data, fileoff + 4)[0])
        return f'protocol {cstring(target[2])}' if target else None
    return f'{seg},{sect}'


args = ['otool', '-tV'] + (['-p', symbol] if symbol else []) + [path]
lines = subprocess.run(args, capture_output=True, text=True).stdout.splitlines()
base = None
started = symbol is None
for line in lines:
    if line.startswith(('-[', '+[')):
        if symbol and started:
            break
        started = True
        base = None
        print(line)
        continue
    if not started:
        continue
    m = re.match(r'([0-9a-f]+)\s+calll\s+0x([0-9a-f]+)', line)
    if m:
        here, target = int(m.group(1), 16), int(m.group(2), 16)
        found = locate(target)
        is_thunk = found and data[found[2]] == 0x8b and data[found[2] + 2:found[2] + 4] == b'\x24\xc3'
        if target == here + 5 or is_thunk:
            base = here + 5
    label = None
    m = re.search(r'(-?0x[0-9a-f]+)\(%e(?:bx|cx|si|di|ax|dx)\)', line)
    if m and base is not None:
        label = describe(base + int(m.group(1), 16))
    # Code built without PIC (the Front Row app itself) loads absolute addresses.
    m = re.search(r'\s(0x[0-9a-f]+),', line)
    if not label and m:
        label = describe(int(m.group(1), 16))
    print(line + ('   ; ' + label if label else ''))
