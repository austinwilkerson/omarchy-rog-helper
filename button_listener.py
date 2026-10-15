#!/usr/bin/env python3
"""Observe only the verified GZ302EA WMI PROG3 event. Never grab or inject input."""
import glob
import os
import select
import struct
import subprocess
import time
from pathlib import Path

SCAN=0xffff01
KEY=202
EVENT=struct.Struct('llHHi')


def matches_frame(events):
    return (4,4,SCAN) in events and (1,KEY,1) in events


def listen(path):
    fd=os.open(path,os.O_RDONLY|os.O_NONBLOCK)
    frame=[]
    last=0
    try:
        while True:
            if not select.select([fd],[],[],5)[0]:
                if not Path(path).exists(): return
                continue
            data=os.read(fd,EVENT.size*64)
            if not data: return
            for _,_,typ,code,value in EVENT.iter_unpack(data):
                if typ==0 and code==0:
                    now=time.monotonic()
                    if matches_frame(frame) and now-last>0.4:
                        subprocess.run(['omarchy-shell','shell','toggle','rog-helper'],timeout=5,check=False)
                        last=now
                    frame=[]
                elif typ in (1,4):
                    frame.append((typ,code,value))
                    if len(frame)>64: frame=[]
    finally:
        os.close(fd)


def main():
    model=Path('/sys/class/dmi/id/product_name').read_text().strip()
    if 'GZ302EA' not in model:
        raise SystemExit('Side-button mapping is verified only on GZ302EA; refusing guessed mapping')
    while True:
        for name in glob.glob('/sys/class/input/event*/device/name'):
            if Path(name).read_text().strip()!='Asus WMI hotkeys': continue
            path='/dev/input/'+Path(name).parents[1].name
            try: listen(path)
            except PermissionError:
                raise SystemExit('WMI input access unavailable. See README side-button setup.')
            except (OSError,subprocess.TimeoutExpired): pass
        time.sleep(3)


if __name__=='__main__': main()
