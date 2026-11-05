"""Check a source tree or print a candidate lock for all registered hooks."""
import hashlib
from pathlib import Path
import re
import stat
import subprocess
import sys

sys.dont_write_bytecode = True
from catalog import BuildError, Plan, plain, relative, selection


def fingerprint(path, kind):
    mode = path.lstat().st_mode
    if not stat.S_ISREG(mode):
        raise BuildError(f"Expected a regular upstream file: {path}")
    data = path.read_bytes()
    if kind == "text-lf":
        data = data.replace(b"\r\n", b"\n")
    return ("100755" if mode & stat.S_IXUSR else "100644", kind, hashlib.sha256(data).hexdigest())


def read_lock(path, version):
    version_line, commit_line, *rows = path.read_text().splitlines()
    commit = commit_line.removeprefix("commit ")
    if version_line != "version " + version or commit_line != "commit " + commit or not re.fullmatch("[0-9a-f]{40}", commit):
        raise BuildError(f"Upstream lock does not match Mastodon {version}: {path}")
    entries = {}
    for row in rows:
        mode, kind, digest, name = row.split(" ", 3)
        if mode not in ("100644", "100755") or kind not in ("text-lf", "raw") or not re.fullmatch("[a-f0-9]{64}", digest) or name in entries:
            raise BuildError(f"Invalid upstream lock entry: {row}")
        relative(name)
        entries[name] = (mode, kind, digest)
    return commit, entries


def check(tree, targets, lock, version):
    for name, (kind, owners) in sorted(targets.items()):
        expected = lock.get(name)
        path = plain(tree, name)
        actual = fingerprint(path, kind) if path.exists() else None
        if not expected or actual != expected:
            raise BuildError(f"Upstream mismatch: {name} (Mastodon {version})\n"
                             f"   Expected: {expected}\n   Actual:   {actual}\n"
                             f"   Required by: {', '.join(sorted(owners))}")


def candidate(tree, version, commit):
    if not re.fullmatch("[0-9a-f]{40}", commit):
        raise BuildError("Expected a full upstream commit ID.")
    def git(*args):
        return subprocess.check_output(["git", "-C", tree, *args], text=True).strip()

    if git("rev-parse", "HEAD") != commit or git("rev-parse", f"v{version}^{{commit}}") != commit:
        raise BuildError(f"Expected the checkout and tag v{version} at {commit}.")
    if git("status", "--porcelain"):
        raise BuildError(f"Expected a clean upstream checkout: {tree}")
    root = Path(__file__).resolve().parent.parent
    modules = selection(root, [p.parent.name for p in (root / "modules").glob("*/module.conf")])
    plan = Plan(root, modules)
    lockfile = root / "loader/upstream.lock"
    previous_version = lockfile.read_text().splitlines()[0].removeprefix("version ")
    previous_commit, previous = read_lock(lockfile, previous_version)
    rows = [f"version {version}", f"commit {commit}"]
    for name, (kind, owners) in sorted(plan.targets.items()):
        actual = fingerprint(plain(tree, name), kind)
        if actual != previous.get(name):
            print(f"Review {name} ({', '.join(sorted(owners))})", file=sys.stderr)
            print(f"  git diff {previous_commit} {commit} -- {name}", file=sys.stderr)
        rows.append(" ".join((*actual, name)))
    for name in sorted(previous.keys() - plan.targets.keys()):
        print(f"No longer managed: {name}", file=sys.stderr)
    print("\n".join(rows))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("Usage: python3 loader/upstream.py CLEAN_TREE VERSION COMMIT > upstream.lock.candidate")
    try:
        candidate(Path(sys.argv[1]), *sys.argv[2:])
    except (BuildError, OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"E: {error}")
