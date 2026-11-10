import unittest
import tempfile
from pathlib import Path
from contextlib import ExitStack
from unittest.mock import patch
import backend
from button_listener import matches_frame

class Validation(unittest.TestCase):
 def test_button_requires_scan_and_press(self):
  self.assertTrue(matches_frame([(4,4,0xffff01),(1,202,1)]))
  for frame in [[(4,4,233),(1,240,1)],[(1,202,1)],[(4,4,0xffff01),(1,202,0)],[(4,4,233),(1,202,1)]]:
   self.assertFalse(matches_frame(frame))
 def test_no_injection_or_unsupported_device(self):
  with patch.object(backend,'aura_devices',return_value=[]), patch.object(backend,'run') as run:
   with self.assertRaises(ValueError): backend.action(['color','/arbitrary/path','#00ff00'])
   run.assert_not_called()
 def test_reject_unsupported_modes_brightness_and_bad_color(self):
  dev={'path':'/test','brightnessLevels':[0,1], 'modes':[{'value':0}], 'effect':[0,0,[1,2,3],[0,0,0],'Med','Right']}
  with patch.object(backend,'aura_devices',return_value=[dev]),patch.object(backend,'set_property') as write:
   for kind,value in [('color','#ffffff;id'),('mode','99'),('brightness','3')]:
    with self.assertRaises(ValueError): backend.action([kind,'/test',value])
   write.assert_not_called()
 def test_mode_keeps_zone_and_other_effect_fields(self):
  dev={'path':'/test','modes':[{'value':1}], 'effect':[0,0,[1,2,3],[4,5,6],'Med','Right']}
  with patch.object(backend,'aura_devices',return_value=[dev]),patch.object(backend,'set_property') as write:
   backend.action(['mode','/test','1'])
   write.assert_called_once_with('/test','LedModeData','(uu(yyy)(yyy)ss)',1,0,1,2,3,4,5,6,'Med','Right')
 def test_reject_bad_charge_and_profile(self):
  with patch.object(backend,'status',return_value={'power':{'profiles':['balanced']}}),patch.object(backend,'run') as run:
   with self.assertRaises(ValueError): backend.action(['profile','turbo'])
   with self.assertRaises(ValueError): backend.action(['charge','101'])
   run.assert_not_called()
 def test_missing_backends_still_produces_status(self):
  with patch.object(backend,'run',side_effect=FileNotFoundError('missing')),patch.object(backend,'sensors',return_value=[]):
   state=backend.status()
   self.assertEqual(state['devices'],[])
   self.assertEqual(state['power']['profiles'],[])
   self.assertEqual(len(state['errors']),2)

 def test_lightbar_targets_only_rear_bar_and_saves_after_success(self):
  with tempfile.TemporaryDirectory() as tmp, ExitStack() as stack:
   stack.enter_context(patch.object(backend,'STATE_DIR',Path(tmp)))
   state=Path(tmp)/'lightbar.json'
   stack.enter_context(patch.object(backend,'LIGHTBAR_STATE',state))
   stack.enter_context(patch.object(backend,'z13_binary',return_value='/usr/bin/z13ctl'))
   stack.enter_context(patch.object(backend,'read',return_value='GZ302EA'))
   run=stack.enter_context(patch.object(backend,'run'))
   backend.action(['color','z13ctl:lightbar','#0000ff'])
   run.assert_called_once_with('/usr/bin/z13ctl','--device','lightbar','apply','--mode','static','--color','0000ff','--brightness','medium')
   self.assertEqual(backend.lightbar_saved()['color'],'#0000ff')
   run.side_effect=RuntimeError('permission denied')
   with self.assertRaises(RuntimeError): backend.action(['color','z13ctl:lightbar','#ff0000'])
   self.assertEqual(backend.lightbar_saved()['color'],'#0000ff')
 def test_lightbar_requires_verified_model_and_backend(self):
  with patch.object(backend,'z13_binary',return_value=None):
   self.assertFalse(backend.lightbar_device()['available'])
   with self.assertRaises(ValueError): backend.action(['color','z13ctl:lightbar','#0000ff'])
  with patch.object(backend,'z13_binary',return_value='/usr/bin/z13ctl'),patch.object(backend,'read',return_value='Other ROG'),patch.object(backend,'run') as run:
   with self.assertRaises(ValueError): backend.action(['color','z13ctl:lightbar','#0000ff'])
   run.assert_not_called()

 def test_keyboard_text_follows_theme_and_manual_color_clears_following(self):
  keyboard = {'path':'/keyboard','name':'Keyboard',
              'effect':[0,0,[255,0,255],[0,0,0],'Med','Right']}
  with tempfile.TemporaryDirectory() as tmp, ExitStack() as stack:
   root = Path(tmp)
   theme = root/'colors.toml'
   theme.write_text('foreground = "#112233"\n')
   stack.enter_context(patch.multiple(backend, STATE_DIR=root, THEME_COLORS=theme))
   stack.enter_context(patch.object(backend,'aura_devices',return_value=[keyboard]))
   install = stack.enter_context(patch.object(backend,'install_theme_hook'))
   write = stack.enter_context(patch.object(backend,'set_property'))

   backend.action(['keyboard-theme-role','/keyboard','foreground'])
   install.assert_called_once()
   self.assertEqual(backend.keyboard_theme_role(),'foreground')
   theme.write_text('accent = "#7aa2f7"\nforeground = "#a9b1d6"\n')
   # Omarchy has already applied its magenta keyboard override.
   write.reset_mock()
   backend.action(['theme-changed'])
   write.assert_called_once_with('/keyboard','LedModeData','(uu(yyy)(yyy)ss)',
                                0,0,169,177,214,0,0,0,'Med','Right')
   backend.action(['color','/keyboard','#ff00ff'])
   self.assertEqual(backend.keyboard_theme_role(),'')
   write.reset_mock()
   backend.action(['theme-changed'])
   write.assert_not_called()

if __name__=='__main__': unittest.main()
