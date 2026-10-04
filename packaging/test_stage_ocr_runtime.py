import hashlib
import importlib.util
from pathlib import Path
import tarfile
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "stage_ocr_runtime", Path(__file__).with_name("stage-ocr-runtime.py")
)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeStagingTests(unittest.TestCase):
    def stage_fixture(self, root, archive, digest=None):
        runtime.ASSETS["fixture"] = [
            ("https://example.invalid/" + archive.name,
             digest or hashlib.sha256(archive.read_bytes()).hexdigest(),
             {"native/runtime.dll": "runtime.dll"},
             {"LICENSE": "Runtime-LICENSE.txt"})
        ]
        runtime.stage("fixture", root / "bin", root / "licenses", root)

    def test_only_selected_flat_files_are_written(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "fixture.nupkg"
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr("native/runtime.dll", b"binary")
                package.writestr("LICENSE", b"license")
                package.writestr("../../outside", b"ignored")
            self.stage_fixture(root, archive)
            self.assertEqual((root / "bin/runtime.dll").read_bytes(), b"binary")
            self.assertEqual((root / "licenses/Runtime-LICENSE.txt").read_bytes(), b"license")
            self.assertEqual(sorted(p.name for p in (root / "bin").iterdir()), ["runtime.dll"])

    def test_checksum_failure_writes_no_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "fixture.nupkg"
            archive.write_bytes(b"not a trusted archive")
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                self.stage_fixture(root, archive, "0" * 64)
            self.assertFalse((root / "bin").exists())

    def test_tar_member_must_be_a_regular_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "fixture.tgz"
            with tarfile.open(archive, "w:gz") as package:
                entry = tarfile.TarInfo("native/runtime.dll")
                entry.type = tarfile.SYMTYPE
                entry.linkname = "../../outside"
                package.addfile(entry)
            with self.assertRaisesRegex(ValueError, "regular runtime file"):
                self.stage_fixture(root, archive)
            self.assertFalse((root / "bin/runtime.dll").exists())


if __name__ == "__main__":
    unittest.main()
