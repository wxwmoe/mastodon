"""Run with python3 -B -m unittest discover -s loader."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from apply import main
from catalog import BuildError, selection
from upstream import fingerprint


class LoaderTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.write("loader/base.conf", "Watch: core\n")
        self.module("base")
        self.module("feature", "Depends: base\nFile: opt/feature\n")
        self.write("modules/feature/overlay/opt/feature", "enabled\n")
        self.seed = self.write("seed", "upstream\n")
        mode, kind, digest = fingerprint(self.seed, "text-lf")
        self.write("loader/upstream.lock", f"version 1\ncommit {'a' * 40}\n{mode} {kind} {digest} core\n")

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def module(self, name, declarations=""):
        self.write(f"modules/{name}/module.conf", declarations)

    def prepare(self, tree, archive, commit):
        tree.mkdir()
        (tree / "core").write_bytes(b"upstream\r\n")
        (tree / "alias").symlink_to("core")

    def test_selection(self):
        self.module("child", "Depends: feature\n")
        self.assertEqual(list(selection(self.root, [" # skip", "child # selected", "feature", "base"])),
                         ["base", "feature", "child"])
        with self.assertRaises(BuildError) as err:
            selection(self.root, ["child", "unknown", "child"])
        for message in ["Duplicate module", "Unknown module", "child -> feature -> base"]:
            self.assertIn(message, str(err.exception))
        self.module("base", "Depends: child\n")
        with self.assertRaisesRegex(BuildError, "Dependency cycle"):
            selection(self.root, ["child", "feature", "base"])

    def test_fingerprints(self):
        path = self.seed
        path.write_bytes(b"a\nb\n")
        expected = fingerprint(path, "text-lf")
        raw = fingerprint(path, "raw")
        path.write_bytes(b"a\r\nb\n")
        os.utime(path, (1, 1))
        self.assertEqual(fingerprint(path, "text-lf"), expected)
        self.assertNotEqual(fingerprint(path, "raw"), raw)
        for contents in (b"\xef\xbb\xbfa\nb\n", b"a\nb", b"a \nb\n", b"a\rb\n"):
            path.write_bytes(contents)
            self.assertNotEqual(fingerprint(path, "text-lf"), expected)
        path.chmod(0o755)
        self.assertEqual(fingerprint(path, "text-lf")[0], "100755")

    def test_transaction_and_empty_rebuild(self):
        dest = self.root / "src"
        with patch("apply.prepare", side_effect=self.prepare) as fetch:
            with self.assertRaisesRegex(BuildError, "not selected"):
                main(self.root, ["feature"], "1")
            fetch.assert_not_called()
            main(self.root, ["feature", "base"], "1")
            self.assertTrue((dest / "opt/feature").is_file())
            self.assertEqual((dest / "core").read_bytes(), b"upstream\r\n")
            inode = dest.stat().st_ino
            def collision(tree, archive, commit):
                self.prepare(tree, archive, commit)
                (tree / "opt").symlink_to("missing")
            fetch.side_effect = collision
            with self.assertRaisesRegex(BuildError, "symbolic link"):
                main(self.root, ["feature", "base"], "1", "--check")
            self.assertEqual(dest.stat().st_ino, inode)
            self.assertTrue((dest / "opt/feature").is_file())
            fetch.side_effect = self.prepare
            main(self.root, [], "1")
            self.assertFalse((dest / "opt").exists())
            self.assertEqual(list(self.root.glob(".wxw-build-*")), [])

    def test_reuse_and_invalidation(self):
        selected = ["feature", "base"]
        dest = self.root / "src"
        overlay = self.root / "modules/feature/overlay/opt/feature"
        with patch("apply.prepare", side_effect=self.prepare) as fetch:
            main(self.root, selected, "1", "--check")
            inode = dest.stat().st_ino
            os.utime(overlay, (1, 1))
            os.utime(dest / "core", (1, 1))
            self.module("unused")
            main(self.root, ["base", "# unused", "feature # enabled"], "1")
            with self.assertRaisesRegex(BuildError, "not selected"):
                main(self.root, ["feature"], "1")
            self.assertEqual(fetch.call_count, 1)
            self.assertEqual(dest.stat().st_ino, inode)

            overlay.write_text("changed\n")
            main(self.root, selected, "1")
            self.assertEqual((dest / "opt/feature").read_text(), "changed\n")
            main(self.root, selected, "1", "--no-cache")
            main(self.root, selected, "1", "--check")
            self.assertEqual(fetch.call_count, 4)

    def test_modified_source_is_preserved_until_forced(self):
        dest = self.root / "src"
        core = dest / "core"
        alias = dest / "alias"

        def retarget_link():
            alias.unlink()
            alias.symlink_to("missing")

        changes = {"content": lambda: core.write_text("edited"), "missing": core.unlink,
                   "mode": lambda: core.chmod(0o755), "extra directory": (dest / "extra").mkdir,
                   "link target": retarget_link}
        for name, change in changes.items():
            with self.subTest(change=name), patch("apply.prepare", side_effect=self.prepare) as fetch:
                main(self.root, [], "1", "--check")
                change()
                inode = dest.stat().st_ino
                with self.assertRaisesRegex(BuildError, "src/ has changed"):
                    main(self.root, [], "1")
                self.assertEqual(dest.stat().st_ino, inode)
                fetch.assert_called_once()

    def test_failure_preserves_published_source_and_state(self):
        state = self.root / ".wxw-source-state"
        dest = self.root / "src"
        with patch("apply.prepare", side_effect=self.prepare):
            main(self.root, [], "1")
            before = state.read_bytes()
            inode = dest.stat().st_ino
            with patch.object(Path, "replace", side_effect=OSError("state write failed")):
                with self.assertRaisesRegex(OSError, "state write failed"):
                    main(self.root, ["base", "feature"], "1")
        self.assertEqual(state.read_bytes(), before)
        self.assertEqual(dest.stat().st_ino, inode)
        self.assertFalse((dest / "opt").exists())

    def test_input_edit_during_assembly_is_not_published(self):
        with patch("apply.prepare", side_effect=self.prepare):
            main(self.root, [], "1")
        dest = self.root / "src"
        before = dest.stat().st_ino
        state = (self.root / ".wxw-source-state").read_bytes()

        def edit_while_preparing(tree, archive, commit):
            self.prepare(tree, archive, commit)
            self.module("feature", "Depends: base\n")

        with patch("apply.prepare", side_effect=edit_while_preparing):
            with self.assertRaisesRegex(BuildError, "inputs changed during assembly"):
                main(self.root, ["base", "feature"], "1")
        self.assertEqual(dest.stat().st_ino, before)
        self.assertEqual((self.root / ".wxw-source-state").read_bytes(), state)
