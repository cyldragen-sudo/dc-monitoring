#!/usr/bin/env python3
"""Install this report and its browser assets into an explicit FineReport webroot.

The legacy DC_MONITORING_3D URL is part of saved report navigation; it now hosts
ordinary HTML/CSS/JavaScript and raster illustrations, not a WebGL renderer.
Only that directory and the single DC_MONITORING report are installation targets.
Existing targets require --replace and are copied to a timestamped backup before
any write. Failures restore those targets. No database or server configuration,
vendor binaries, licensing files, or other report projects are modified.
"""

import argparse
from datetime import datetime, timezone
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def install(webroot, replace=False, report=None):
    """Stage a complete payload, then install with recoverable replacement.

    FineReport's static server does not consistently recognize .mjs MIME types,
    so deployment uses .js and rewrites module references in text assets. Source
    files and tests remain .mjs in Git. Symlink targets are refused to keep writes
    inside the explicitly selected webroot.
    """
    webroot = Path(webroot).resolve()
    reportlets = webroot / "WEB-INF/reportlets"
    if not reportlets.is_dir():
        raise ValueError("Expected an existing FineReport webroot with WEB-INF/reportlets.")
    report_dir = reportlets / "DC_MONITORING"
    report_target = report_dir / "Infrastructure_Overview.fvs"
    runtime = webroot / "DC_MONITORING_3D"
    for path in (reportlets, report_dir, report_target, runtime):
        if path.is_symlink() or not path.resolve().is_relative_to(webroot):
            raise ValueError("Installation targets must not escape webroot through symlinks.")
    targets = (report_target, runtime)
    if any(path.exists() for path in targets) and not replace:
        raise FileExistsError("DC dashboard already exists. Review it before using --replace.")
    report = Path(report or ROOT / "dashboard/report/Infrastructure_Overview.fvs").resolve()
    if not report.is_file():
        raise FileNotFoundError(report)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    backup = ROOT / "build/backups" / stamp
    with tempfile.TemporaryDirectory(prefix="dc-install-") as temporary:
        staged = Path(temporary) / "runtime"
        staged.mkdir()
        for source in (ROOT / "dashboard/scene").iterdir():
            if source.name.startswith("test_") or source.suffix not in (".html", ".css", ".mjs"):
                continue
            destination = staged / (source.stem + ".js" if source.suffix == ".mjs" else source.name)
            destination.write_text(source.read_text().replace(".mjs", ".js"))
        shutil.copytree(ROOT / "dashboard/scene/assets", staged / "assets")
        saved = {}
        for target in targets:
            if target.exists():
                backup.mkdir(parents=True, exist_ok=True)
                saved[target] = backup / target.name
                if target.is_dir():
                    shutil.copytree(target, saved[target])
                else:
                    shutil.copy2(target, saved[target])
        try:
            report_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(report, report_target)
            if runtime.exists():
                shutil.rmtree(runtime)
            shutil.copytree(staged, runtime)
        except Exception:
            # Roll back only the two owned targets, never their containing folders.
            for target in targets:
                if target.is_dir():
                    shutil.rmtree(target)
                elif target.exists():
                    target.unlink()
                if target in saved:
                    if saved[target].is_dir():
                        shutil.copytree(saved[target], target)
                    else:
                        shutil.copy2(saved[target], target)
            raise
    print("Installed DC_MONITORING report and DC_MONITORING_3D runtime.")
    if saved:
        print("Previous files backed up to:", backup)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--webroot", required=True, type=Path)
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--report", type=Path, help="Use a freshly built .fvs instead of the bundled report.")
    args = parser.parse_args()
    install(args.webroot, args.replace, args.report)
