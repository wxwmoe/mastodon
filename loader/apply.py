"""Prepare or verify the source tree for the selected wxw modules."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from textwrap import indent

sys.dont_write_bytecode = True
from catalog import BuildError, Plan, RAILS_HOOKS, plain, selection
from upstream import check, read_lock


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def digest_paths(root, paths, *, allow_links=False):
    digest = hashlib.sha256()

    def visit(path):
        mode = path.lstat().st_mode
        digest.update(os.fsencode(path.relative_to(root)) + b"\0" + f"{mode:o}\0".encode())
        if stat.S_ISDIR(mode):
            for child in sorted(path.iterdir()):
                visit(child)
        elif stat.S_ISREG(mode):
            contents = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    contents.update(chunk)
            digest.update(contents.digest())
        elif allow_links and stat.S_ISLNK(mode):
            digest.update(os.fsencode(os.readlink(path)) + b"\0")
        else:
            raise BuildError(f"Unexpected file type: {path}")

    for path in sorted(paths):
        visit(path)
    return digest.hexdigest()


def input_digest(root, selected, plan):
    paths = [p for p in (root / "loader").iterdir()
             if p.name not in {"patches", "__pycache__"} and not p.name.startswith("test_")]
    paths.extend(plan.patches)
    paths.extend(root / "modules" / name for name in selected)
    return digest_paths(root, paths)


def can_reuse(state, dest, inputs):
    if not dest.is_dir() or not state.exists():
        return False
    # A valid state is 130 bytes; include one extra byte to detect trailing data.
    with state.open("rb") as stream:
        saved = re.fullmatch(rb"([0-9a-f]{64}) ([0-9a-f]{64})\n", stream.read(131))
    if not saved:
        raise BuildError("Invalid source state. Run 'bash build.sh --check' to recreate it.")
    if digest_paths(dest, [dest], allow_links=True) != saved[2].decode():
        raise BuildError("Generated src/ has changed. Save your changes and run 'bash build.sh --check' to regenerate it.")
    return inputs == saved[1].decode()


def prepare(tree, archive, commit):
    url = f"https://codeload.github.com/mastodon/mastodon/tar.gz/{commit}"
    run("curl", "--fail", "--silent", "--show-error", "--location", "--retry", "2",
        "--connect-timeout", "20", "--output", archive, url)
    tree.mkdir()
    run("tar", "-xzf", archive, "--strip-components=1", "--no-same-owner", "-C", tree)


def assemble(root, tree, stage, plan, selected, lock, version):
    check(tree, plan.targets, lock, version)
    for owner, script in plan.assets:
        output = stage / ("assets-" + owner)
        output.mkdir()
        run("bash", script, cwd=output)
        for path in sorted(output.rglob("*")):
            if path.is_symlink():
                raise BuildError(f"{owner}: Unexpected symbolic link: {path}")
            if path.is_file():
                plan.add(path.relative_to(output).as_posix(), path, owner)

    generated = {}
    if plan.styles:
        generated["app/javascript/styles/mastodon/wxw_components.scss"] = "".join(
            f"@use '{style}';\n" for style in plan.styles)
    if plan.schemas:
        definitions = indent("\n\n".join(plan.schemas), "      ")
        generated["db/wxw_schema.rb"] = (
            "# frozen_string_literal: true\n\nmodule WxwSchema\n  def self.apply(schema)\n"
            f"    schema.instance_exec do\n{definitions}\n    end\n  end\nend\n")
    registries = {f"{hook}_extensions": (RAILS_HOOKS[hook], concerns)
                  for hook, concerns in plan.registered.items()}
    if "status_settings" in selected:
        registries["status_setting_fields"] = ("StatusSettingFields", plan.fields.values())
    for filename, (constant, concerns) in registries.items():
        includes = "".join(f"  include {concern}\n" for concern in concerns)
        generated[f"app/models/concerns/wxw/{filename}.rb"] = (
            f"# frozen_string_literal: true\n\nmodule Wxw::{constant}\n"
            "  extend ActiveSupport::Concern\n" + includes + "end\n")
    for name, data in generated.items():
        path = stage / "generated" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        plan.add(name, path, "loader")

    for name, (source, owner) in plan.files.items():
        path = plain(tree, name)
        if not source.is_file():
            raise BuildError(f"{owner}: Missing implementation: {source}")
        for parent in path.parents:
            if parent == tree:
                break
            if parent.relative_to(tree).as_posix() in plan.files or (parent.exists() and not parent.is_dir()):
                raise BuildError(f"{owner}: Directory collision: {parent}")
        if path.exists() and plan.targets.get(name, (None,))[0] != "raw":
            raise BuildError(f"{owner}: Refusing to overwrite: {name}")

    locale_outputs = {}
    for name, additions in plan.locales.items():
        messages = json.loads((tree / name).read_bytes())
        overlap = messages.keys() & additions.keys()
        if overlap:
            raise BuildError(f"{name}: Refusing to replace locale keys: {sorted(overlap)}")
        messages.update(additions)
        locale_outputs[name] = json.dumps(messages, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    for name in plan.patched | ({"config/themes.yml"} if plan.themes else set()):
        path = tree / name
        data = path.read_bytes()
        if b"\r\n" in data:
            path.write_bytes(data.replace(b"\r\n", b"\n"))
    for name, content in locale_outputs.items():
        (tree / name).write_text(content)
    if plan.themes:
        with (tree / "config/themes.yml").open("a") as config:
            for theme in plan.themes:
                if f"app/javascript/styles/{theme}.scss" not in plan.files:
                    raise BuildError(f"Missing theme entry point: {theme}")
                config.write(f"{theme}: styles/{theme}.scss\n")
    for patch in plan.patches:
        args = ["patch", "--batch", "--forward", "--silent", "--fuzz=0",
                "--no-backup-if-mismatch", "-p1", "-d", tree, "-i", patch]
        run(*args, "--dry-run")
        run(*args)
    for name, (source, _) in plan.files.items():
        path = tree / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if name in plan.targets:
            shutil.copyfile(source, path)
        else:
            shutil.copy2(source, path)


def publish(tree, dest):
    if dest.is_symlink() or (dest.exists() and not dest.is_dir()):
        raise BuildError(f"Expected a build directory: {dest}")
    if not dest.exists():
        tree.rename(dest)
        return
    # Both names always refer to complete trees, even if the process is interrupted.
    libc = ctypes.CDLL(None, use_errno=True)
    if not hasattr(libc, "renameat2"):
        raise BuildError("Atomic directory exchange requires Linux renameat2.")
    if libc.renameat2(-100, os.fsencode(tree), -100, os.fsencode(dest), 2) != 0:
        raise OSError(ctypes.get_errno(), "Cannot exchange the staged and previous source directories")


def main(root, lines, version, mode=""):
    if mode not in ("", "--check", "--no-cache"):
        raise BuildError(f"Unknown build option: {mode}")
    selected = selection(root, lines)
    plan = Plan(root, selected)
    commit, lock = read_lock(root / "loader/upstream.lock", version)
    missing = plan.targets.keys() - lock.keys()
    if missing:
        raise BuildError("Missing upstream fingerprints: " + ", ".join(sorted(missing)))
    print("Reading module list... Done", flush=True)
    print("Selected modules: " + (", ".join(selected) or "none (version metadata only)"), flush=True)
    dest = plain(root, "src")
    state = plain(root, ".wxw-source-state")
    if dest.exists() and not dest.is_dir():
        raise BuildError(f"Expected a build directory: {dest}")
    if state.exists() and not state.is_file():
        raise BuildError(f"Expected a regular source state file: {state}")
    inputs = input_digest(root, selected, plan)
    if not mode and can_reuse(state, dest, inputs):
        print(f"Reusing verified Mastodon {version}~wxw sources.", flush=True)
        return
    print(f"Preparing Mastodon {version} ({commit})...", flush=True)
    with tempfile.TemporaryDirectory(prefix=".wxw-build-", dir=root) as name:
        stage = Path(name)
        tree = stage / "src"
        prepare(tree, stage / "upstream.tar.gz", commit)
        assemble(root, tree, stage, plan, selected, lock, version)
        source = digest_paths(tree, [tree], allow_links=True)
        if input_digest(root, selected, plan) != inputs:
            raise BuildError("Build inputs changed during assembly. Retry the build.")
        staged_state = stage / "state"
        staged_state.write_text(f"{inputs} {source}\n", encoding="ascii")
        had_source = dest.exists()
        publish(tree, dest)
        try:
            staged_state.replace(state)
        except OSError:
            if had_source:
                publish(tree, dest)
            else:
                dest.rename(tree)
            raise
    print(f"Mastodon {version}~wxw sources ready.", flush=True)


if __name__ == "__main__":
    try:
        main(Path(__file__).resolve().parent.parent, sys.stdin, *sys.argv[1:])
    except (BuildError, OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"E: {error}")
