"""Count hand-written MoonBit library lines in a Git revision of this module."""

import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(["git", "-C", ROOT, *args]).decode("utf-8")


def main(revision):
    tree = git("rev-parse", "--verify", revision + "^{tree}").strip()
    totals = [0, 0]
    print("file\tcode\twith_word")
    for name in git("ls-tree", "-r", "--name-only", tree).splitlines():
        path = PurePosixPath(name)
        if path.parent.as_posix() not in (".", "scgi") or path.suffix != ".mbt":
            continue
        if name.endswith(("_test.mbt", "_wbtest.mbt")):
            continue
        lines = [s.strip() for s in git("show", f"{tree}:{name}").splitlines()]
        code = [s for s in lines if s and not s.startswith("//")]
        with_word = sum(bool(re.search(r"[a-zA-Z0-9_]", s)) for s in code)
        print(f"{name}\t{len(code)}\t{with_word}")
        totals[0] += len(code)
        totals[1] += with_word
    print("TOTAL", *totals, sep="\t")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "HEAD")
