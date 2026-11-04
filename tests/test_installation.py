"""Safety checks for installation into an isolated mock FineReport webroot.

The tests cover overwrite protection, backup preservation, module serving and
project isolation. They never require a running FineReport server or touch an
installed report. PostgreSQL integration is separately exercised by CI.
"""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installer", ROOT / "scripts/install_dashboard.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallationTests(unittest.TestCase):
    def test_fresh_install_refusal_backup_and_isolation(self):
        with tempfile.TemporaryDirectory() as temporary:
            webroot = Path(temporary)
            reportlets = webroot / "WEB-INF/reportlets"
            other = reportlets / "UNRELATED_PROJECT/keep.txt"
            other.parent.mkdir(parents=True)
            other.write_text("unchanged")
            installer.install(webroot)
            report = reportlets / "DC_MONITORING/Infrastructure_Overview.fvs"
            runtime = webroot / "DC_MONITORING_3D"
            self.assertEqual(report.read_bytes(), (ROOT / "dashboard/report/Infrastructure_Overview.fvs").read_bytes())
            self.assertTrue((runtime / "app.js").is_file())
            self.assertNotIn(".mjs", (runtime / "index.html").read_text())
            self.assertFalse(list(runtime.glob("test_*")))
            report.write_bytes(b"prior report")
            with self.assertRaises(FileExistsError):
                installer.install(webroot)
            installer.install(webroot, replace=True)
            backups = list((ROOT / "build/backups").glob("*/Infrastructure_Overview.fvs"))
            self.assertTrue(any(p.read_bytes() == b"prior report" for p in backups))
            self.assertEqual(other.read_text(), "unchanged")

    def test_failed_replacement_restores_both_owned_targets(self):
        with tempfile.TemporaryDirectory() as temporary:
            webroot = Path(temporary)
            report = webroot / "WEB-INF/reportlets/DC_MONITORING/Infrastructure_Overview.fvs"
            report.parent.mkdir(parents=True)
            report.write_bytes(b"original report")
            runtime = webroot / "DC_MONITORING_3D"
            runtime.mkdir()
            (runtime / "keep.txt").write_text("original runtime")
            copytree = installer.shutil.copytree

            def fail_staged_copy(source, destination, *args, **kwargs):
                # Inject a failure after the old runtime was removed, exercising
                # the recovery path rather than an early precondition rejection.
                if Path(source).name == "runtime" and Path(destination).resolve() == runtime.resolve():
                    raise OSError("simulated deployment failure")
                return copytree(source, destination, *args, **kwargs)

            with patch.object(installer.shutil, "copytree", side_effect=fail_staged_copy):
                with self.assertRaises(OSError):
                    installer.install(webroot, replace=True)
            self.assertEqual(report.read_bytes(), b"original report")
            self.assertEqual((runtime / "keep.txt").read_text(), "original runtime")

    def test_invalid_webroot_and_symlink_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            webroot = Path(temporary) / "root"
            webroot.mkdir()
            with self.assertRaises(ValueError):
                installer.install(webroot)
            (webroot / "WEB-INF/reportlets").mkdir(parents=True)
            outside = Path(temporary) / "outside"
            outside.mkdir()
            (webroot / "DC_MONITORING_3D").symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                installer.install(webroot, replace=True)
            self.assertEqual(list(outside.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
