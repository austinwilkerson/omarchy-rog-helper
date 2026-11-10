import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import fnlock

spec = importlib.util.spec_from_file_location(
    "fnlock_setup", Path(__file__).resolve().parents[1] / "scripts/fnlock-setup.py"
)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class FnLockChanges(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        for field, value in {
            "STATE": root, "MODE": root / "mode", "SETUP": root / "setup.json",
            "LUA": root / "fnlock.lua",
        }.items():
            mock = patch.object(fnlock, field, value)
            mock.start()
            self.addCleanup(mock.stop)
        fnlock.MODE.write_text("media\n")
        fnlock.SETUP.write_text("{}")
        for name, value in (("supported", True), ("check_setup", None), ("check_applied", True)):
            mock = patch.object(fnlock, name, return_value=value)
            mock.start()
            self.addCleanup(mock.stop)

    def test_toggle_and_explicit_selection_share_saved_mode(self):
        with patch.object(fnlock, "apply") as apply:
            self.assertEqual(fnlock.change("toggle"), "function")
            self.assertEqual(fnlock.mode(), "function")
            self.assertEqual(fnlock.change("media"), "media")
            self.assertEqual(fnlock.mode(), "media")
            self.assertEqual([args[0] for args, _ in apply.call_args_list], ["function", "media"])

    def test_failed_live_change_restores_saved_and_live_mode(self):
        with patch.object(fnlock, "apply", side_effect=[RuntimeError("rejected"), None]) as apply:
            with self.assertRaisesRegex(RuntimeError, "Previous mode restored"):
                fnlock.change("function")
            self.assertEqual(fnlock.mode(), "media")
            self.assertEqual([args[0] for args, _ in apply.call_args_list], ["function", "media"])


class SetupChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.input = root / "input.lua"
        self.binds = root / "bindings.lua"
        (root / "hyprland.lua").write_text('require("hypr.input")\n')
        self.wmi = 'hl.device({ name = "asus-wmi-hotkeys", enabled = false })\n'
        self.input.write_text(self.wmi + setup.LEGACY_INPUT)
        self.binds.write_text(setup.LEGACY_BIND + '-- keep F9\n')
        mock = patch.multiple(setup, HYPR=root, INPUT=self.input, BINDS=self.binds)
        mock.start()
        self.addCleanup(mock.stop)

    def test_migration_keeps_unrelated_rules_and_rejects_unknown_conflict(self):
        with patch.object(fnlock, "expect_binding"), patch.object(fnlock, "hypr", return_value="[]"):
            before, after, legacy = setup.inspect_config()
            self.assertTrue(legacy)
            self.assertIn(self.wmi, after[self.input])
            self.assertEqual(after[self.binds], setup.LEGACY_MARKER + '-- keep F9\n')
            self.assertEqual(after[self.input].replace(setup.hook(), setup.LEGACY_INPUT), before[self.input])
            self.input.write_text(before[self.input] + 'hl.device({name="asustek-computer-inc.-gz302ea-keyboard"})\n')
            with self.assertRaisesRegex(RuntimeError, "Review the existing Z13"):
                setup.inspect_config()

    def test_rejected_config_reload_restores_previous_contents(self):
        before = {self.input: self.input.read_text()}
        with patch.object(setup, "reload", side_effect=[RuntimeError("invalid"), None]):
            with self.assertRaisesRegex(RuntimeError, "invalid"):
                setup.edit_config(before, {self.input: "bad edit"}, lambda: None)
        self.assertEqual(self.input.read_text(), before[self.input])

    @unittest.skipUnless(shutil.which("xkbcli"), "requires xkbcli")
    def test_german_variant_preserves_layout_and_options_with_all_media_keys(self):
        settings = dict(rules="", model="", layout="de", variant="nodeadkeys", options="compose:caps")
        baseline = fnlock.command("xkbcli", "compile-keymap", "--output-format", "1",
                                  "--layout", "de", "--variant", "nodeadkeys", "--options", "compose:caps")
        media = setup.build_keymap(settings)
        for name in ("<AD06>", "<CAPS>"):
            baseline_key = next(line for line in baseline.splitlines() if "key " + name in line)
            self.assertIn(baseline_key, media)
        self.assertIn("German (no dead keys)" + fnlock.KEYMAP_SUFFIX, media)
        self.assertIn("key <FK06> { [ Print ] };", media)
        self.assertIn("key <FK09> { [ XF86Display ] };", media)
        self.assertIn("key <FK11> { [ XF86KbdLightOnOff ] };", media)
        self.assertIn("key <FK12> { [ XF86RFKill ] };", media)
