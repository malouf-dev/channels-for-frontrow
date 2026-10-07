#!/usr/bin/env python3
"""Turn `otool -ov` output for a 32-bit (legacy runtime) binary into a compact
class listing:

    @class Name : Superclass
      - instanceSelector   typeEncoding
      + classSelector      typeEncoding
    @category Name (CategoryName)
      ...

Usage, with a copy of BackRow taken from the iMac:
    otool -arch i386 -ov BackRow > backrow-objc.txt
    tools/backrow/class-list.py backrow-objc.txt > backrow-classes.txt
"""
import re
import sys

out = []
superclass = ''
category = ''
selector = ''
meta = False
for line in open(sys.argv[1]).read().splitlines():
    s = line.strip()
    if s == 'Meta Class':
        meta = True
        continue
    if s.startswith('defs[') or s.startswith('Class Definitions'):
        meta = False
        continue
    m = re.match(r'super_class 0x[0-9a-f]+ ?(\S*)', s)
    if m:
        superclass = m.group(1)
        continue
    m = re.match(r'name 0x[0-9a-f]+ (\S+)', s)
    if m:
        if not meta:
            out.append(f'@class {m.group(1)} : {superclass}')
        continue
    m = re.match(r'category_name 0x[0-9a-f]+ (\S+)', s)
    if m:
        category = m.group(1)
        continue
    m = re.match(r'class_name 0x[0-9a-f]+ (\S+)', s)
    if m:
        out.append(f'@category {m.group(1)} ({category})')
        continue
    if s.startswith('instance_methods'):
        meta = False
        continue
    if s.startswith('class_methods'):
        meta = True
        continue
    m = re.match(r'method_name 0x[0-9a-f]+ (\S+)', s)
    if m:
        selector = m.group(1)
        continue
    m = re.match(r'method_types 0x[0-9a-f]+ (\S+)', s)
    if m:
        out.append(f"  {'+' if meta else '-'} {selector}   {m.group(1)}")
print('\n'.join(out))
