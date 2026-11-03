"""Launch one host and three clients and check real local ENet replication."""
import argparse
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time
from udp_impairment import UDPImpairment

parser = argparse.ArgumentParser()
parser.add_argument("--godot", required=True)
parser.add_argument("--latency-ms",type=float,default=0,help="One-way delay on local UDP relay")
parser.add_argument("--jitter-ms",type=float,default=0)
parser.add_argument("--packet-loss",type=float,default=0,help="Fraction, e.g. 0.005 for 0.5 percent")
args = parser.parse_args()
if args.latency_ms < 0 or args.jitter_ms < 0 or not 0 <= args.packet_loss <= 0.2: parser.error("Invalid impairment values")
project = Path(__file__).resolve().parents[1]
output = Path(tempfile.mkdtemp(prefix="station7-coop-"))
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    relay = UDPImpairment(port,args.latency_ms,args.jitter_ms,args.packet_loss) if args.latency_ms or args.jitter_ms or args.packet_loss else None
processes = []
streams = []


def launch(role, slot=0):
    log = (output / f"{role}{slot}.log").open("w")
    streams.append(log)
    cmd = [args.godot, "--headless", "--path", str(project), "--script",
           "res://tests/coop_test_runner.gd", "--", f"--role={role}", f"--slot={slot}",
           f"--test-dir={output}", f"--port={port if role == 'host' or not relay else relay.port}"]
    process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
    processes.append((role, slot, process))


try:
    launch("host")
    deadline = time.monotonic() + 150
    while not (output / "listening.json").exists():
        if processes[0][2].poll() is not None or time.monotonic() > deadline:
            raise RuntimeError("Host failed to start: " + (output / "host0.log").read_text())
        time.sleep(0.1)
    # Serial handshake makes numbered slots deterministic for fixture routing.
    for slot in range(1, 4):
        launch("client", slot)
        time.sleep(0.5)
    outsider_started = False
    while any(p.poll() is None for _, _, p in processes):
        if not outsider_started and (output / "allow-outsider.json").exists():
            launch("outsider")
            outsider_started = True
        if time.monotonic() > deadline:
            raise RuntimeError("Co-op suite exceeded 150 seconds")
        time.sleep(0.2)
    failed = False
    for role, slot, process in processes:
        log = (output / f"{role}{slot}.log").read_text()
        print(f"{role}{slot}: exit {process.returncode}, {log.count('PASS:')} checks")
        if process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
            failed = True
            print(log[-12000:])
    if relay: print(f"UDP relay: {args.latency_ms}ms one-way, ±{args.jitter_ms}ms jitter, {args.packet_loss*100:.1f}% loss; {relay.forwarded} forwarded, {relay.dropped} dropped")
    print("Logs:", output)
    raise SystemExit(1 if failed else 0)
finally:
    for _, _, process in processes:
        if process.poll() is None:
            process.terminate()
    for _, _, process in processes:
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    for stream in streams:
        stream.close()
    if relay: relay.close()
