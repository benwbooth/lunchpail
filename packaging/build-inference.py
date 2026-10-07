#!/usr/bin/env python3
"""Build and stage self-contained CPU and GPU workers on each native host.

This is a developer/packaging step, never an end-user dependency. Keep CPU
workers separate so a missing GPU loader or broken driver cannot prevent
CPU inference (or bring down the Qt application).
"""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('target/inference'))
    parser.add_argument('--target-root', type=Path, default=Path('target/inference'))
    parser.add_argument('--target')
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    system = platform.system()
    if system not in ('Linux', 'Windows', 'Darwin'):
        parser.error(f'Unsupported native host: {system}')
    backend = 'metal' if system == 'Darwin' else 'vulkan'
    extension = '.exe' if system == 'Windows' else ''
    env = os.environ.copy()
    env['GGML_NATIVE'] = 'OFF'
    env['GGML_METAL_EMBED_LIBRARY'] = 'ON'
    # Never tune distributed binaries to the build runner's CPU instruction set.
    if 'target-cpu=native' in env.get('RUSTFLAGS', ''):
        parser.error('Remove target-cpu=native before building portable workers')
    args.output.mkdir(parents=True, exist_ok=True)
    target = args.target or env.get('CARGO_BUILD_TARGET')
    for flavor in ('cpu', 'gpu'):
        build = Path(str(args.target_root) + '-' + flavor)
        command = ['cargo', 'build', '--locked', '--release', '--no-default-features',
                   '-p', 'lunchpail-llm', '-p', 'lunchpail-speech', '--target-dir', str(build)]
        if args.offline:
            command.append('--offline')
        if target:
            command += ['--target', target]
        if flavor == 'gpu':
            command += ['--features', f'lunchpail-llm/{backend},lunchpail-speech/{backend}']
        subprocess.run(command, env=env, check=True)
        release = build / target / 'release' if target else build / 'release'
        for engine in ('llm', 'speech'):
            source = release / f'lunchpail-{engine}{extension}'
            destination = args.output / f'lunchpail-{engine}-{flavor}{extension}'
            # Replace atomically: an active child may still be using the old
            # executable when the development watcher rebuilds its successor.
            temporary = destination.with_suffix(destination.suffix + '.new')
            shutil.copy2(source, temporary)
            os.replace(temporary, destination)
    for engine in ('llm', 'speech'):
        # macOS links Metal into every worker, and initialising it on a
        # virtualised CI GPU can take well over 30 seconds.
        result = subprocess.run([str((args.output / f'lunchpail-{engine}-cpu{extension}').resolve())],
                                input='{"operation":"probe"}\n', text=True, capture_output=True, check=True, timeout=300)
        import json
        reply = json.loads(result.stdout)
        if reply.get('error') or reply.get('device') != 'CPU':
            raise RuntimeError(f'CPU runtime probe failed: {reply}')


if __name__ == '__main__':
    main()
