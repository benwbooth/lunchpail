"""Live Qt audio routing on a private PulseAudio server; no real device changes.

Run in the Qt development shell with pulseaudio and pactl on PATH. Ordinary
test discovery skips this check when the native audio tools are unavailable.
"""
from array import array
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(
    sys.platform == "linux"
    and all(shutil.which(tool) for tool in ("pulseaudio", "pactl", "parec", "qmltestrunner")),
    "requires Linux, PulseAudio, and the Qt development shell",
)
class AudioDeviceSwitch(unittest.TestCase):
    def test_live_output_switch_while_playing_and_muted(self):
        with tempfile.TemporaryDirectory(prefix="lunchpail-audio-route-") as directory:
            root = Path(directory)
            env = dict(os.environ, PULSE_SERVER=f"unix:{root}/pulse.sock", QT_QPA_PLATFORM="offscreen")
            env.pop("PULSE_SINK", None)
            env.pop("PULSE_SOURCE", None)
            server_env = dict(
                env, XDG_RUNTIME_DIR=directory, PULSE_RUNTIME_PATH=directory,
                DBUS_SESSION_BUS_ADDRESS=f"unix:path={root}/no-session-bus",
            )
            server = None
            runner = None
            with (root / "pulse.log").open("w+") as server_log, (root / "qml.log").open("w+") as qml_log:
                try:
                    server = subprocess.Popen([
                        "pulseaudio", "-n", "--daemonize=no", "--use-pid-file=no",
                        "--exit-idle-time=-1", "--log-target=stderr",
                        f"--load=module-native-protocol-unix socket={root}/pulse.sock auth-anonymous=1",
                        "--load=module-null-sink sink_name=route_a sink_properties=device.description=Route_A",
                        "--load=module-null-sink sink_name=route_b sink_properties=device.description=Route_B",
                    ], env=server_env, stdout=server_log, stderr=subprocess.STDOUT)

                    def pactl(*args):
                        return subprocess.check_output(["pactl", *args], env=env, text=True, timeout=5)

                    deadline = time.monotonic() + 10
                    while not (root / "pulse.sock").exists():
                        self.assertIsNone(server.poll(), (root / "pulse.log").read_text())
                        self.assertLess(time.monotonic(), deadline, "private audio server did not start")
                        time.sleep(0.05)
                    while True:
                        sinks = {item["name"]: item["index"] for item in json.loads(pactl("-f", "json", "list", "sinks"))}
                        if "route_a" in sinks and "route_b" in sinks:
                            break
                        self.assertLess(time.monotonic(), deadline, "private audio sinks did not load")
                        time.sleep(0.05)
                    pactl("set-default-sink", "route_a")
                    runner = subprocess.Popen([
                        "qmltestrunner", "-input", str(Path(__file__).parent / "native" / "tst_audio_device_switch.qml"),
                    ], env=env, stdout=qml_log, stderr=subprocess.STDOUT)

                    def wait_for(marker):
                        deadline = time.monotonic() + 25
                        while marker not in (root / "qml.log").read_text():
                            self.assertIsNone(runner.poll(), (root / "qml.log").read_text())
                            self.assertLess(time.monotonic(), deadline, (root / "qml.log").read_text())
                            time.sleep(0.025)

                    for suffix, name in (("B", "route_b"), ("A", "route_a")):
                        wait_for(f"AUDIO_ROUTE_READY_{suffix}")
                        pactl("set-default-sink", name)
                        wait_for(f"AUDIO_ROUTE_VERIFY_{suffix}")
                        streams = json.loads(pactl("-f", "json", "list", "sink-inputs"))
                        active = [stream for stream in streams if not stream["corked"]]
                        self.assertTrue(active, "QML reported playback but no live audio stream exists")
                        self.assertTrue(all(stream["sink"] == sinks[name] for stream in active), active)
                        self.assertTrue(all(not stream["mute"] for stream in active), active)
                        # Capture only the private null-sink monitor containing
                        # our synthetic fixture. Never open a microphone or the
                        # user's system output monitor.
                        recorder = subprocess.Popen([
                            "parec", "--raw", "--format=s16le", "--rate=48000",
                            "--channels=2", "--latency-msec=20", "--process-time-msec=10",
                            f"--device={name}.monitor",
                        ], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                        try:
                            raw, error = recorder.communicate(timeout=3)
                        except subprocess.TimeoutExpired:
                            recorder.terminate()
                            raw, error = recorder.communicate(timeout=5)
                        self.assertTrue(raw, f"No monitor samples: {error.decode(errors='replace')}")
                        samples = array("h")
                        samples.frombytes(raw[:len(raw) // 2 * 2])
                        if sys.byteorder != "little":
                            samples.byteswap()
                        peak = max((abs(value) for value in samples), default=0)
                        self.assertGreater(peak, 50, f"{name} is routed but silent ({len(raw)} captured bytes)")
                        print(f"{name}: decoded audio reached the output (PCM peak {peak})")
                    self.assertEqual(runner.wait(timeout=10), 0, (root / "qml.log").read_text())
                    print("Live audio routing: playing A->B and muted/reopened B->A passed")
                finally:
                    for process in (runner, server):
                        if process is not None and process.poll() is None:
                            process.terminate()
                            try:
                                process.wait(timeout=5)
                            except subprocess.TimeoutExpired:
                                process.kill()
                                process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
