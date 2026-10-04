#!/usr/bin/env python3
"""Stage the separate GPU OCR runtime; Sherpa keeps its own static CPU runtime."""

import argparse
import hashlib
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile


# Microsoft-published binaries, pinned independently of the speech dependency.
ASSETS = {
    "windows-x86_64": [
        (
            "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime.directml/1.24.4/microsoft.ml.onnxruntime.directml.1.24.4.nupkg",
            "57e9f11b73437bef7a309496135d4c1f96b1a8e9ddba60013fa27bfc1d788681",
            {"runtimes/win-x64/native/onnxruntime.dll": "onnxruntime.dll",
             "runtimes/win-x64/native/onnxruntime_providers_shared.dll": "onnxruntime_providers_shared.dll"},
            {"LICENSE": "ONNXRuntime-LICENSE.txt", "ThirdPartyNotices.txt": "ONNXRuntime-ThirdPartyNotices.txt"},
        ),
        (
            "https://api.nuget.org/v3-flatcontainer/microsoft.ai.directml/1.15.4/microsoft.ai.directml.1.15.4.nupkg",
            "4e7cb7ddce8cf837a7a75dc029209b520ca0101470fcdf275c1f49736a3615b9",
            {"bin/x64-win/DirectML.dll": "DirectML.dll"},
            {"LICENSE.txt": "DirectML-LICENSE.txt", "LICENSE-CODE.txt": "DirectML-LICENSE-CODE.txt",
             "ThirdPartyNotices.txt": "DirectML-ThirdPartyNotices.txt"},
        ),
    ],
    "macos-arm64": [
        (
            "https://github.com/microsoft/onnxruntime/releases/download/v1.28.0/onnxruntime-osx-arm64-1.28.0.tgz",
            "1268b359718099bde2cedb55787f182a130067bc4f31e8c88478c445b850d3d8",
            {"onnxruntime-osx-arm64-1.28.0/lib/libonnxruntime.1.28.0.dylib": "libonnxruntime.dylib"},
            {"onnxruntime-osx-arm64-1.28.0/LICENSE": "ONNXRuntime-LICENSE.txt",
             "onnxruntime-osx-arm64-1.28.0/ThirdPartyNotices.txt": "ONNXRuntime-ThirdPartyNotices.txt"},
        ),
    ],
}


def stage(platform, runtime_dir, licenses_dir, archives_dir=None):
    for url, expected_digest, binaries, licenses in ASSETS[platform]:
        name = url.rsplit("/", 1)[-1]
        with tempfile.TemporaryDirectory(prefix="lunchpail-ocr-") as temporary:
            archive_path = Path(temporary) / name
            if archives_dir is not None:
                shutil.copyfile(archives_dir / name, archive_path)
            else:
                with urllib.request.urlopen(url, timeout=120) as response:
                    with archive_path.open("wb") as output:
                        shutil.copyfileobj(response, output)
            with archive_path.open("rb") as source:
                checksum = hashlib.sha256()
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    checksum.update(chunk)
                digest = checksum.hexdigest()
            if digest != expected_digest:
                raise ValueError(f"OCR runtime checksum mismatch: {name}")

            if name.endswith(".nupkg"):
                archive = zipfile.ZipFile(archive_path)
                read_entry = archive.read
            else:
                archive = tarfile.open(archive_path, "r:gz")

                def read_entry(member):
                    entry = archive.getmember(member)
                    if not entry.isfile():
                        raise ValueError(f"Expected a regular runtime file: {member}")
                    return archive.extractfile(entry).read()

            # Only selected files with fixed basenames are written, never archive paths.
            with archive:
                for destinations, directory in [(binaries, runtime_dir), (licenses, licenses_dir)]:
                    directory.mkdir(parents=True, exist_ok=True)
                    for member, basename in destinations.items():
                        if PurePosixPath(basename).name != basename:
                            raise ValueError(f"Invalid staging basename: {basename}")
                        data = read_entry(member)
                        (directory / basename).write_bytes(data)
                        print(f"Staged {basename}: {len(data)} bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=ASSETS)
    parser.add_argument("--runtime-dir", type=Path, required=True)
    parser.add_argument("--licenses-dir", type=Path, required=True)
    parser.add_argument("--archives-dir", type=Path, help="Use already-downloaded pinned archives")
    options = parser.parse_args()
    stage(options.platform, options.runtime_dir, options.licenses_dir, options.archives_dir)
