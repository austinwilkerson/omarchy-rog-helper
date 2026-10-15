#!/usr/bin/env python3
"""ROG Helper: unprivileged clients of existing ASUS / power-profile services."""
import concurrent.futures
import glob
import json
import os
import shutil
import tempfile
import fcntl
import re
import subprocess
import sys
from pathlib import Path

DEST = 'xyz.ljones.Asusd'
IFACE = 'xyz.ljones.Aura'
MODES = {0: 'Static', 1: 'Breathe', 10: 'Pulse'}
STATE_DIR = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'rog-helper'
LIGHTBAR_STATE = STATE_DIR / 'lightbar.json'
Z13_MODES = {0:'static',1:'breathe',2:'cycle',3:'rainbow'}


def z13_binary():
    return shutil.which('z13ctl')


def lightbar_saved():
    try:
        state=json.loads(LIGHTBAR_STATE.read_text())
        if state['brightness'] not in (0,1,2,3) or state['mode'] not in Z13_MODES or not re.fullmatch('#[0-9a-fA-F]{6}',state['color']):
            raise ValueError('Invalid saved state')
        return state
    except (OSError,ValueError,KeyError,TypeError):
        return {'brightness':2,'mode':0,'color':'#00eeee'}


def lightbar_device():
    available=bool(z13_binary())
    return dict(path='z13ctl:lightbar',name='Lightbar',brightnessLevels=[0,1,2,3],
        modes=[{'value':k,'label':v.title()} for k,v in Z13_MODES.items()],
        available=available, note=('z13ctl · last applied settings; reapply after resume if needed' if available else
        'Rear lightbar needs z13ctl. asusd accepted commands but did not light it on GZ302EA.'), **lightbar_saved())


def apply_lightbar(kind,value):
    binary=z13_binary()
    if not binary: raise ValueError('Install z13ctl and configure lightbar permissions; see README')
    if 'GZ302EA' not in (read('/sys/class/dmi/id/product_name') or ''):
        raise ValueError('z13ctl fallback is verified only for GZ302EA')
    STATE_DIR.mkdir(parents=True,exist_ok=True,mode=0o700)
    with (STATE_DIR/'lightbar.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        state=lightbar_saved()
        if kind=='brightness':
            n=int(value)
            if n not in (0,1,2,3): raise ValueError('Unsupported brightness')
            state['brightness']=n
        elif kind=='mode':
            n=int(value)
            if n not in Z13_MODES: raise ValueError('Unsupported mode')
            state['mode']=n
        elif kind=='color':
            if not re.fullmatch('#[0-9a-fA-F]{6}',value): raise ValueError('Invalid RGB color')
            state['color']=value
        if state['brightness']==0:
            run(binary,'--device','lightbar','off')
        else:
            run(binary,'--device','lightbar','apply','--mode',Z13_MODES[state['mode']],
                '--color',state['color'][1:],'--brightness',['off','low','medium','high'][state['brightness']])
        fd,tmp=tempfile.mkstemp(dir=STATE_DIR,prefix='.lightbar-')
        try:
            with os.fdopen(fd,'w') as out: json.dump(state,out)
            os.replace(tmp,LIGHTBAR_STATE)
        finally:
            if os.path.exists(tmp): os.unlink(tmp)



def run(*args):
    p = subprocess.run(args, text=True, capture_output=True, timeout=8)
    if p.returncode:
        raise RuntimeError(p.stderr.strip() or p.stdout.strip() or f'{args[0]} failed')
    return p.stdout.strip()


def read(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


def aura_devices():
    tree = run('busctl', '--system', '--list', 'tree', DEST)
    devices = []
    for path in tree.splitlines():
        if not path.startswith('/xyz/ljones/aura/'):
            continue
        raw = json.loads(run('busctl', '--system', '--json=short', 'call', DEST,
                             path, 'org.freedesktop.DBus.Properties', 'GetAll', 's', IFACE))
        props = {k: v['data'] for k, v in raw['data'][0].items()}
        typ = props.get('DeviceType')
        # asusd 6.4: LaptopKeyboard=0, LaptopLightbar=1. Others keep their identity.
        devices.append(dict(path=path, name={0:'Keyboard',1:'Lightbar'}.get(typ, 'Aura device'),
                            brightness=props.get('Brightness'),
                            brightnessLevels=props.get('SupportedBrightness', []),
                            modes=[dict(value=k,label=MODES[k]) for k in props.get('SupportedBasicModes',[]) if k in MODES],
                            effect=props.get('LedModeData'), mode=props.get('LedMode'),
                            color='#%02x%02x%02x' % tuple(props['LedModeData'][2])))
    if 'GZ302EA' in (read('/sys/class/dmi/id/product_name') or ''):
        devices=[d for d in devices if d['name']!='Lightbar']
        devices.append(lightbar_device())
    return sorted(devices, key=lambda d: (d["name"] != "Keyboard", d["path"]))


def sensors():
    values=[]
    for hw in glob.glob('/sys/class/hwmon/hwmon*'):
        name=read(hw+'/name')
        if name not in ('asus','asus_custom_fan_curve','k10temp','amdgpu'):
            continue
        for f in sorted(glob.glob(hw+'/fan*_input')+glob.glob(hw+'/temp*_input')):
            val=read(f)
            if val is None:
                continue
            istemp=Path(f).name.startswith('temp')
            label=read(f.replace('_input','_label')) or (name+' '+Path(f).name.split('_')[0])
            values.append(dict(label=label,value=round(int(val)/1000,1) if istemp else int(val),unit='°C' if istemp else 'RPM'))
    return values


def status():
    result={'model':read('/sys/class/dmi/id/product_name') or 'Unknown model', 'errors':[]}
    def profiles():
        text=run('powerprofilesctl','list')
        return {'profiles':re.findall(r'^\s*\*?\s*([a-z][a-z-]+):\s*$',text,re.M),'profile':run('powerprofilesctl','get')}
    jobs={'devices':aura_devices,'power':profiles,'sensors':sensors}
    with concurrent.futures.ThreadPoolExecutor() as pool:
        futures={k:pool.submit(v) for k,v in jobs.items()}
        for k,f in futures.items():
            try: result[k]=f.result()
            except (RuntimeError,OSError,ValueError,subprocess.TimeoutExpired) as e:
                result[k]=[] if k!='power' else {'profiles':[],'profile':''}
                result['errors'].append(k+': '+str(e))
    result['batteries']=[]
    for battery in glob.glob('/sys/class/power_supply/*'):
        if read(battery+'/type')!='Battery': continue
        result['batteries'].append(dict(name=Path(battery).name,capacity=read(battery+'/capacity'),
            status=read(battery+'/status'),limit=read(battery+'/charge_control_end_threshold')))
    result['platformProfile']=read('/sys/firmware/acpi/platform_profile')
    return result


def set_property(path, prop, signature, *values):
    return run('busctl','--system','set-property',DEST,path,IFACE,prop,signature,*map(str,values))


def action(args):
    kind,*values=args
    if kind=='profile' and len(values)==1:
        if values[0] not in status()['power']['profiles']: raise ValueError('Unsupported power profile')
        run('powerprofilesctl','set',values[0])
    elif kind=='charge' and len(values)==1:
        value=int(values[0])
        if value not in (60,80,100): raise ValueError('Choose 60, 80 or 100 percent')
        if not any(x['limit'] is not None for x in status()['batteries']): raise ValueError('Charge limit unavailable')
        run('asusctl','battery','limit',str(value))
    elif kind in ('brightness','mode','color') and len(values)==2:
        path,value=values
        if path=='z13ctl:lightbar':
            return apply_lightbar(kind,value)
        devices={x['path']:x for x in aura_devices()}
        if path not in devices: raise ValueError('Aura device disappeared')
        device=devices[path]
        if kind=='brightness':
            level=int(value)
            if level not in device['brightnessLevels']: raise ValueError('Unsupported brightness')
            set_property(path,'Brightness','u',level)
        else:
            effect=device['effect']
            if kind=='mode':
                mode=int(value)
                if mode not in [x['value'] for x in device['modes']]: raise ValueError('Unsupported mode')
                effect[0]=mode
            else:
                if not re.fullmatch('#[0-9a-fA-F]{6}',value): raise ValueError('Invalid RGB color')
                effect[2]=[int(value[i:i+2],16) for i in (1,3,5)]
            set_property(path,'LedModeData','(uu(yyy)(yyy)ss)',effect[0],effect[1],*effect[2],*effect[3],effect[4],effect[5])
    else:
        raise ValueError('Unknown action or invalid arguments')


if __name__=='__main__':
    try:
        if sys.argv[1:]==['status']: print(json.dumps(status()))
        else:
            action(sys.argv[1:])
            print(json.dumps({'ok':True}))
    except Exception as e:
        print(json.dumps({'ok':False,'error':str(e)}))
        sys.exit(1)
