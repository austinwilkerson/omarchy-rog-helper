#!/usr/bin/env python3
"""ROG Helper: unprivileged clients of existing ASUS / power-profile services."""
import concurrent.futures
from contextlib import contextmanager
import glob
import html
import json
import os
import shutil
import tempfile
import fcntl
import re
import subprocess
import sys
from pathlib import Path
import fnlock
import power_state

DEST = 'xyz.ljones.Asusd'
IFACE = 'xyz.ljones.Aura'
PLATFORM = 'xyz.ljones.Platform'
MODES = {0: 'Static', 1: 'Breathe', 10: 'Pulse'}
STATE_DIR = power_state.STATE_DIR
LIGHTBAR_STATE = STATE_DIR / 'lightbar.json'
THEME_COLORS = Path.home()/'.local/state/omarchy/current/theme/colors.toml'
THEME_HOOK = Path.home()/'.config/omarchy/hooks/theme-set.d/90-rog-helper-theme.sh'
THEME_ROLES = {'accent': ('accent', 'color4'), 'foreground': ('foreground', 'color7'),
               'urgent': ('red', 'color1')}
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


def profiles():
    text=run('powerprofilesctl','list')
    return {'profiles':re.findall(r'^\s*\*?\s*([a-z][a-z-]+):\s*$',text,re.M),'profile':run('powerprofilesctl','get')}


def one_shot_supported():
    try:
        info = run('busctl', '--system', 'introspect', DEST, '/xyz/ljones', PLATFORM)
        return re.search(r'(?m)^\.OneShotFullCharge\s+method\s', info) is not None
    except (OSError, RuntimeError, subprocess.TimeoutExpired):
        return False


def charge_once():
    if power_state.on_battery() is not False:
        raise ValueError('Plug in the charger before starting a one-time charge.')
    batteries = [p for p in power_state.POWER_SUPPLY.glob('BAT*')
                 if read(p/'type') == 'Battery']
    if len(batteries) != 1:
        raise ValueError('Could not identify the internal battery.')
    threshold = batteries[0]/'charge_control_end_threshold'
    limit = power_state.number(threshold)
    if limit is None or not 20 <= limit < 100:
        raise ValueError('One-time charging needs a charge limit below 100%.')
    # Call the same method as `asusctl battery oneshot` with no percent argument.
    # asusd preserves the normal limit and restores it when AC is disconnected.
    run('busctl', '--system', 'call', DEST, '/xyz/ljones', PLATFORM, 'OneShotFullCharge')
    if power_state.number(threshold) != 100:
        raise RuntimeError('The temporary 100% limit was not confirmed.')
    return f'Charging to 100% once. Unplugging restores your {limit}% limit.'


def status():
    result={'model':read('/sys/class/dmi/id/product_name') or 'Unknown model', 'errors':[], 'fnlock':fnlock.status()}
    result['keyboardThemeRole'] = keyboard_theme_role()
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
            status=read(battery+'/status'),limit=read(battery+'/charge_control_end_threshold'),
            **power_state.battery_readings(Path(battery))))
    result['onBattery'] = power_state.on_battery()
    result['chargeOnce'] = (sum(b['name'].startswith('BAT') for b in result['batteries']) == 1
                            and one_shot_supported())
    result['refresh'] = power_state.refresh_status(result['onBattery'])
    result['powerLimits'] = power_state.power_limits()
    result['platformProfile']=read('/sys/firmware/acpi/platform_profile')
    return result


def set_property(path, prop, signature, *values):
    return run('busctl','--system','set-property',DEST,path,IFACE,prop,signature,*map(str,values))


def keyboard_theme_role():
    role = read(STATE_DIR/'keyboard-theme-role')
    return role if role in THEME_ROLES else ''


@contextmanager
def keyboard_theme_lock():
    STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE_DIR/'keyboard-theme.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def theme_role_color(role):
    if role not in THEME_ROLES:
        raise ValueError('Unsupported keyboard theme color')
    colors = dict(re.findall(r"""(?m)^\s*(accent|foreground|red|color[147])\s*=\s*["']?(#[0-9a-fA-F]{6})\b""",
                             read(THEME_COLORS) or ''))
    preferred, fallback = THEME_ROLES[role]
    color = colors.get(preferred) or colors.get(fallback)
    if not color:
        raise ValueError('The active theme is missing that color')
    return color.lower()


def install_theme_hook():
    script = Path(__file__).resolve().parent/'scripts'/THEME_HOOK.name
    if THEME_HOOK.is_symlink() or (THEME_HOOK.exists() and THEME_HOOK.read_bytes() != script.read_bytes()):
        raise ValueError('A different ROG Helper theme hook already exists')
    if not THEME_HOOK.exists():
        run('omarchy', 'hook', 'install', 'theme-set', str(script))


def apply_aura_effect(device, kind, value):
    effect = list(device['effect'])
    if kind == 'mode':
        mode = int(value)
        if mode not in [x['value'] for x in device['modes']]:
            raise ValueError('Unsupported mode')
        effect[0] = mode
    else:
        if not re.fullmatch('#[0-9a-fA-F]{6}', value):
            raise ValueError('Invalid RGB color')
        effect[2] = [int(value[i:i+2], 16) for i in (1, 3, 5)]
    set_property(device['path'], 'LedModeData', '(uu(yyy)(yyy)ss)', effect[0], effect[1],
                 *effect[2], *effect[3], effect[4], effect[5])


def follow_keyboard_theme(path, role):
    with keyboard_theme_lock():
        devices = [d for d in aura_devices() if d['name'] == 'Keyboard']
        if len(devices) != 1 or devices[0]['path'] != path:
            raise ValueError('Theme following is available for the ASUS laptop keyboard')
        color = theme_role_color(role)
        install_theme_hook()
        apply_aura_effect(devices[0], 'color', color)
        fnlock.atomic_write(STATE_DIR/'keyboard-theme-role', role + '\n')


def refresh_keyboard_theme():
    if not keyboard_theme_role():
        return
    with keyboard_theme_lock():
        role = keyboard_theme_role()
        if not role:
            return
        keyboards = [d for d in aura_devices() if d['name'] == 'Keyboard']
        if len(keyboards) != 1:
            return
        apply_aura_effect(keyboards[0], 'color', theme_role_color(role))


def action(args):
    kind,*values=args
    if kind=='fnlock' and len(values)==1:
        return {'function': 'Function keys', 'media': 'Media keys'}[fnlock.change(values[0])]
    elif kind=='fnlock-hotkey' and len(values)==1:
        return fnlock_hotkey(values[0])
    elif kind=='keyboard-theme-role' and len(values)==2:
        follow_keyboard_theme(*values)
    elif kind=='theme-changed' and not values:
        refresh_keyboard_theme()
    elif kind=='charge-once' and not values:
        return charge_once()
    elif kind=='auto-refresh' and len(values)==1:
        power_state.change_refresh(values[0])
    elif kind=='refresh-sync' and not values:
        power_state.sync_refresh()
    elif kind=='profile' and len(values)==1:
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
        elif device.get('name') == 'Keyboard':
            with keyboard_theme_lock():
                # Re-read after the lock in case a theme change updated the effect.
                keyboard = next((d for d in aura_devices() if d['path'] == path), None)
                if keyboard is None:
                    raise ValueError('Aura device disappeared')
                apply_aura_effect(keyboard, kind, value)
                if kind == 'color':
                    (STATE_DIR/'keyboard-theme-role').unlink(missing_ok=True)
        else:
            apply_aura_effect(device, kind, value)
    else:
        raise ValueError('Unknown action or invalid arguments')


def fnlock_hotkey(key):
    if not fnlock.supported() or not fnlock.SETUP.is_file():
        raise RuntimeError('Optional Z13 Fn Lock is not set up.')
    with fnlock.lock():
        fnlock.check_setup()
        fnlock.check_applied('media', require_keyboard=True)
        if key == 'profile':
            power = profiles()
            choices = [p for p in ('power-saver', 'balanced', 'performance') if p in power['profiles']]
            if not choices:
                raise RuntimeError('No supported power profiles are available.')
            current = choices.index(power['profile']) if power['profile'] in choices else -1
            target = choices[(current + 1) % len(choices)]
            run('powerprofilesctl', 'set', target)
            return 'Power profile: ' + target
        if key == 'airplane':
            radios = json.loads(run('rfkill', '--json'))['rfkilldevices']
            if not radios:
                raise RuntimeError('No wireless radios are available.')
            block = any(radio['soft'] == 'unblocked' for radio in radios)
            run('rfkill', 'block' if block else 'unblock', 'all')
            return 'Airplane mode on' if block else 'Airplane mode off'
        raise ValueError('Unknown Fn Lock hotkey')


def notify(message):
    try:
        subprocess.run(['notify-send', 'ROG Helper', html.escape(message)], timeout=2, check=False)
    except (OSError, subprocess.TimeoutExpired):
        pass


if __name__=='__main__':
    args = sys.argv[1:]
    notify_action = args == ['fnlock', 'toggle', '--notify'] or args[:1] == ['fnlock-hotkey']
    try:
        if args==['status']: print(json.dumps(status()))
        else:
            if args == ['fnlock', 'toggle', '--notify']:
                args.pop()
            message = action(args)
            if notify_action:
                notify(message or 'Software Fn Lock changed')
            print(json.dumps({'ok':True, 'message':message}))
    except Exception as e:
        if notify_action:
            notify(str(e))
        print(json.dumps({'ok':False,'error':str(e)}))
        sys.exit(1)
