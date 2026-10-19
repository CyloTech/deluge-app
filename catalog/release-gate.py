#!/usr/bin/env python3
"""Release gate for a newly built Deluge image.

Usage: catalog/release-gate.py repo.cylo.net/deluge:<tag>

Run on the dedicated builder after `docker build` and before `docker push`.
Exits zero only when the local image passes every check below and the
authenticated registry reports that the tag does not exist yet.

1. Registry: the previous release tag must be readable (proves registry
   authentication and transport) and the new tag must be definitively absent.
2. Package versions: Deluge 2.2.0 with libtorrent 2.0.10.
3. Fresh install with one TCP and two combined ports: daemon and torrent TCP
   reachable, DHT ping answered through the UDP torrent port, Web UI answers,
   deluged and deluge-web both run with a 65535 open-files soft limit.
4. Restart of the same container: same checks.
5. Update from the previous published image on the same volume: test data and
   the customer's Deluge and ltConfig preferences kept, same checks after
   recreation and after a further restart.

Test containers use a disposable bridge, a test volume and a stubbed install
callback. No customer data, production API or tracker is used.
"""
import json
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time
import uuid

PREVIOUS_IMAGE = "repo.cylo.net/deluge@sha256:3599a7b253355610cc97f8e033bc39b164e0ef638633205c4483ad9b0526273a"
PREVIOUS_TAG = "repo.cylo.net/deluge:2.2.0-lt-2.0.10.0-2"
# Customer preferences that differ from the image templates; an update must keep them.
CORE_PREFS = {"max_active_downloading": 4, "max_connections_global": 300,
              "max_connections_per_torrent": 60, "dht": False,
              "move_completed": False, "stop_seed_ratio": 0.5}
LTCONFIG_PREFS = {"connections_limit": 1234}
NOFILE = 65535
PREFIX = "deluge-release-gate-" + uuid.uuid4().hex[:12]
containers = []


def docker(*args, check=True):
    result = subprocess.run(["docker", *args], text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f"docker {args[0]} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def check_registry(image):
    result = subprocess.run(["docker", "manifest", "inspect", PREVIOUS_TAG],
                            text=True, capture_output=True)
    if result.returncode:
        sys.exit(f"FAIL registry: cannot read {PREVIOUS_TAG}; state is indeterminate: {result.stderr.strip()}")
    result = subprocess.run(["docker", "manifest", "inspect", image],
                            text=True, capture_output=True)
    if result.returncode == 0:
        sys.exit(f"FAIL registry: {image} already exists; refusing to replace it")
    if result.stderr.strip() != f"no such manifest: {image}":
        sys.exit(f"FAIL registry: state of {image} is indeterminate: {result.stderr.strip()}")
    print(f"PASS registry readable and {image} not yet published", flush=True)


def check_versions(image):
    out = docker("run", "--rm", "--platform", "linux/amd64", "--entrypoint", "deluged",
                 image, "--version")
    assert re.search(r"^deluged 2\.2\.0$", out, re.M), out
    assert re.search(r"^libtorrent: 2\.0\.10(\.\d+)?$", out, re.M), out
    print("PASS Deluge 2.2.0 with libtorrent 2.0.10", flush=True)


def free_ports():
    held = []
    try:
        ports = []
        for _ in range(3):
            tcp = socket.socket()
            tcp.bind(("127.0.0.1", 0))
            port = tcp.getsockname()[1]
            udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            udp.bind(("127.0.0.1", port))
            held.extend((tcp, udp))
            ports.append(port)
        return ports
    finally:
        for sock in held:
            sock.close()


def start(name, image, ports, stub):
    # Production containers get nofile 65535:65535 from the catalogue ulimits.
    args = ["run", "-d", "--name", name, "--platform", "linux/amd64",
            "--network", PREFIX, "--init", "--log-driver", "none",
            "--ulimit", f"nofile={NOFILE}:{NOFILE}",
            "--mount", f"type=volume,src={PREFIX},dst=/torrents",
            "--mount", f"type=bind,src={stub},dst=/release-test/bin,readonly",
            "-e", "PATH=/release-test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "-e", "INSTANCE_ID=deluge-release-gate",
            "-e", "DELUGE_USERNAME=gatetest", "-e", "DELUGE_PASSWORD=gatetest-local-only",
            "-e", f"DAEMON_PORT={ports[0]}", "-e", f"FIRST_PORT={ports[1]}",
            "-e", f"LAST_PORT={ports[2]}",
            "-p", f"127.0.0.1:{ports[0]}:{ports[0]}/tcp"]
    for port in ports[1:]:
        args.extend(["-p", f"127.0.0.1:{port}:{port}/tcp", "-p", f"127.0.0.1:{port}:{port}/udp"])
    containers.append(name)
    docker(*args, image)


def soft_nofile(name, program):
    status = docker("exec", name, "supervisorctl", "pid", program)
    code = f"""
import os, re
children = [int(p) for p in os.listdir('/proc') if p.isdigit()]
def descendants(root):
    found, frontier = [], [root]
    while frontier:
        parent = frontier.pop()
        for pid in children:
            try:
                ppid = int(open(f'/proc/{{pid}}/stat').read().rsplit(')', 1)[1].split()[1])
            except OSError:
                continue
            if ppid == parent:
                found.append(pid); frontier.append(pid)
    return found
for pid in [{int(status)}] + descendants({int(status)}):
    try:
        comm = open(f'/proc/{{pid}}/comm').read().strip()
    except OSError:
        continue
    if comm == '{program}':
        limits = open(f'/proc/{{pid}}/limits').read()
        print(re.search(r'Max open files\\s+(\\d+)', limits).group(1)); break
"""
    return int(docker("exec", name, "python3", "-c", code))


CONF_CODE = """
import json, pathlib, sys
def load(p):
    s = p.read_text(); d = json.JSONDecoder(); h, n = d.raw_decode(s); return h, d.decode(s[n:].lstrip())
def save(p, h, c):
    p.write_text(json.dumps(h, indent=4) + json.dumps(c, indent=4, sort_keys=True))
base = pathlib.Path('/torrents/config/deluge')
core, lt = base / 'core.conf', base / 'ltconfig.conf'
if sys.argv[1] == 'set':
    prefs = json.loads(sys.argv[2])
    h, c = load(core); c.update(prefs['core']); save(core, h, c)
    h, c = load(lt); c['settings'].update(prefs['ltconfig']); save(lt, h, c)
else:
    c = load(core)[1]; l = load(lt)[1]['settings']
    print(json.dumps({'core': {k: c.get(k) for k in json.loads(sys.argv[2])['core']},
                      'ltconfig': {k: l.get(k) for k in json.loads(sys.argv[2])['ltconfig']}}))
"""


def prefs_arg():
    return json.dumps({"core": CORE_PREFS, "ltconfig": LTCONFIG_PREFS})


def set_prefs(image):
    # Edit the stopped volume, as a customer would have done through Deluge.
    docker("run", "--rm", "--platform", "linux/amd64", "--entrypoint", "python3",
           "--mount", f"type=volume,src={PREFIX},dst=/torrents",
           image, "-c", CONF_CODE, "set", prefs_arg())


def check_prefs(name):
    found = json.loads(docker("exec", name, "python3", "-c", CONF_CODE, "get", prefs_arg()))
    assert found == {"core": CORE_PREFS, "ltconfig": LTCONFIG_PREFS}, found


def verify(name, ports, expect_nofile=True):
    # Deluge config files contain a format header followed by the config object.
    config_code = """
import json, pathlib
s=pathlib.Path('/torrents/config/deluge/core.conf').read_text()
d=json.JSONDecoder(); _,n=d.raw_decode(s); c=d.decode(s[n:].lstrip())
print(json.dumps({k:c[k] for k in ('listen_ports','daemon_port','random_port')}))
"""
    web_code = "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1/', timeout=5).status)"
    deadline = time.monotonic() + 120
    while True:
        try:
            config = json.loads(docker("exec", name, "python3", "-c", config_code))
            assert config["listen_ports"] == [ports[1], ports[1]], config
            assert config["daemon_port"] == ports[0], config
            assert config["random_port"] is False, config
            for port in ports[:2]:
                with socket.create_connection(("127.0.0.1", port), timeout=1):
                    pass
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                udp.settimeout(2)
                ping = b'd1:ad2:id20:abcdefghijklmnopqrste1:q4:ping1:t2:ab1:y1:qe'
                udp.sendto(ping, ("127.0.0.1", ports[1]))
                reply, _ = udp.recvfrom(4096)
                assert b'1:t2:ab' in reply and b'1:y1:r' in reply, 'Unexpected UDP response'
            status = docker("exec", name, "supervisorctl", "status")
            states = {line.split()[0]: line.split()[1] for line in status.splitlines() if len(line.split()) > 1}
            assert states.get("deluged") == "RUNNING", status
            assert states.get("deluge-web") == "RUNNING", status
            assert docker("exec", name, "python3", "-c", web_code) == "200"
            limits = {p: soft_nofile(name, p) for p in ("deluged", "deluge-web")}
            break
        except (AssertionError, OSError, RuntimeError, ValueError, json.JSONDecodeError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(1)
    if expect_nofile:
        assert limits == {"deluged": NOFILE, "deluge-web": NOFILE}, limits
    print(f"PASS {name}: config, TCP/UDP ports, Web UI; open-files soft limits {limits}", flush=True)
    return limits


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r"repo\.cylo\.net/deluge:[A-Za-z0-9._-]+", sys.argv[1]):
        sys.exit("usage: release-gate.py repo.cylo.net/deluge:<tag>")
    image = sys.argv[1]
    docker("image", "inspect", image)
    check_versions(image)

    with tempfile.TemporaryDirectory(prefix=PREFIX + "-") as temp:
        stub = Path(temp)
        stub.chmod(0o755)
        curl = stub / "curl"
        curl.write_text('#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\n\\r\\n"\n')
        curl.chmod(0o755)
        docker("network", "create", PREFIX)
        docker("volume", "create", PREFIX)
        try:
            ports = free_ports()
            fresh = PREFIX + "-fresh"
            start(fresh, image, ports, str(stub))
            verify(fresh, ports)
            docker("restart", fresh)
            verify(fresh, ports)
            docker("rm", "-f", fresh)
            containers.remove(fresh)
            docker("volume", "rm", PREFIX)
            docker("volume", "create", PREFIX)

            # Existing customer data from the previous published image.
            old = PREFIX + "-previous"
            start(old, PREVIOUS_IMAGE, ports, str(stub))
            before = verify(old, ports, expect_nofile=False)
            print(f"INFO previous image open-files soft limits {before}", flush=True)
            docker("exec", old, "sh", "-c", "printf preserved > /torrents/release-gate-marker")
            docker("stop", old)
            docker("rm", old)
            containers.remove(old)
            set_prefs(image)

            updated = PREFIX + "-updated"
            start(updated, image, ports, str(stub))
            verify(updated, ports)
            assert docker("exec", updated, "cat", "/torrents/release-gate-marker") == "preserved"
            check_prefs(updated)
            docker("restart", updated)
            verify(updated, ports)
            check_prefs(updated)
            print("PASS update from previous image kept data and preferences, raised limits", flush=True)
        finally:
            for name in containers:
                docker("rm", "-f", name, check=False)
            docker("volume", "rm", PREFIX, check=False)
            docker("network", "rm", PREFIX, check=False)

    # Last: the registry precondition immediately before push.
    check_registry(image)


if __name__ == "__main__":
    main()
