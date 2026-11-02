#!/usr/bin/env python3
"""在临时用户数据目录运行 UI / 动效回归，不读写玩家的真实设置。"""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    args = parser.parse_args()
    godot = shutil.which(args.godot)
    if not godot:
        parser.error("未找到 Godot；请用 --godot 指定 Godot 4.7 可执行文件。")
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="majiang-ui-tests-") as data_dir:
        data_root = Path(data_dir)
        env = os.environ.copy()
        env["MAJIANG_TEST_DATA_ROOT"] = str(data_root)
        for key, folder in {
            "HOME": "home", "USERPROFILE": "home", "XDG_DATA_HOME": "data",
            "XDG_CONFIG_HOME": "config", "APPDATA": "data", "LOCALAPPDATA": "data",
        }.items():
            path = data_root / folder
            path.mkdir(exist_ok=True)
            env[key] = str(path)
        for flags in [
            ["--editor", "--import"],
            ["--script", "tests/ui_regression.gd"],
            ["--script", "tests/effects_regression.gd"],
            ["--script", "tests/effects_regression.gd", "--", "--verify-saved"],
            ["--quit-after", "10"],
        ]:
            print("\nRunning:", " ".join(flags), flush=True)
            result = subprocess.run(
                [godot, "--headless", "--path", str(repo), *flags],
                cwd=repo, env=env, capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=120,
            )
            output = result.stdout + result.stderr
            print(output, end="", flush=True)
            # Godot 某些运行时错误不会改变退出码，不能把这些错误当成测试通过。
            if result.returncode or re.search(r"^(?:SCRIPT )?ERROR:", output, re.MULTILINE):
                return result.returncode or 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
