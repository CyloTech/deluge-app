#!/usr/bin/env python3
"""Test the existing release image with the proposed catalogue port layout.

Run on the dedicated builder. Creates only uniquely named disposable containers,
a disposable Docker network, a test volume and a callback stub. No production API
or torrent tracker is contacted; the empty client may query public DHT bootstrap
nodes. No customer configuration is used.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import uuid

IMAGE = "repo.cylo.net/deluge@sha256:bd878dd1d131d9ce428519f98ebc3f8a9fd180f86a0cc5718ecac552dbf0747b"
PREFIX = "deluge-port-test-" + uuid.uuid4().hex[:12]
containers = []


def docker(*args, check=True):
    result = subprocess.run(["docker", *args], text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f"Docker {args[0]} failed: {result.stderr.strip()}")
    return result.stdout.strip()


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


def start(name, ports, combined, stub):
    args = ["run", "-d", "--name", name, "--platform", "linux/amd64",
            "--network", PREFIX, "--init", "--log-driver", "none",
            "--mount", f"type=volume,src={PREFIX},dst=/torrents",
            "--mount", f"type=bind,src={stub},dst=/release-test/bin,readonly",
            "-e", "PATH=/release-test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "-e", "INSTANCE_ID=deluge-catalogue-test",
            "-e", "DELUGE_USERNAME=porttest", "-e", "DELUGE_PASSWORD=porttest-local-only",
            "-e", f"DAEMON_PORT={ports[0]}", "-e", f"FIRST_PORT={ports[1]}",
            "-e", f"LAST_PORT={ports[2]}"]
    for index, port in enumerate(ports):
        args.extend(["-p", f"127.0.0.1:{port}:{port}/tcp"])
        if combined and index > 0:
            args.extend(["-p", f"127.0.0.1:{port}:{port}/udp"])
    containers.append(name)
    docker(*args, IMAGE)


def verify(name, ports, combined):
    bindings = json.loads(docker("inspect", "--format", "{{json .HostConfig.PortBindings}}", name))
    expected = {f"{p}/tcp" for p in ports}
    if combined:
        expected.update(f"{p}/udp" for p in ports[1:])
    assert set(bindings) == expected, bindings
    for key, values in bindings.items():
        assert values == [{"HostIp": "127.0.0.1", "HostPort": key.split('/')[0]}]

    # Deluge config files contain a format header followed by the config object.
    code = """
import json, pathlib
s=pathlib.Path('/torrents/config/deluge/core.conf').read_text()
d=json.JSONDecoder(); _,n=d.raw_decode(s); c=d.decode(s[n:].lstrip())
print(json.dumps({k:c[k] for k in ('listen_ports','daemon_port','random_port')}))
"""
    deadline = time.monotonic() + 90
    while True:
        try:
            config = json.loads(docker("exec", name, "python3", "-c", code))
            assert config["listen_ports"] == [ports[1], ports[1]], config
            assert config["daemon_port"] == ports[0], config
            assert config["random_port"] is False, config
            for port in ports[:2]:
                with socket.create_connection(("127.0.0.1", port), timeout=1):
                    pass
            if combined:
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                    udp.settimeout(2)
                    ping = b'd1:ad2:id20:abcdefghijklmnopqrste1:q4:ping1:t2:ab1:y1:qe'
                    udp.sendto(ping, ("127.0.0.1", ports[1]))
                    reply, _ = udp.recvfrom(4096)
                    assert b'1:t2:ab' in reply and b'1:y1:r' in reply, 'Unexpected UDP response'
            break
        except (AssertionError, OSError, RuntimeError, json.JSONDecodeError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(1)
    # Deluged and its Web UI must be supervised as the image's unprivileged user.
    status = docker("exec", name, "supervisorctl", "status")
    assert "deluged" in status and "deluge-web" in status and "FATAL" not in status, status
    print(f"PASS {name}: correct config and TCP" + ("/UDP mapping; DHT ping answered" if combined else " mapping"), flush=True)


def main():
    with tempfile.TemporaryDirectory(prefix=PREFIX + "-") as temp:
        stub = Path(temp)
        stub.chmod(0o755)
        curl = stub / "curl"
        curl.write_text('#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\n\\r\\n"\n')
        curl.chmod(0o755)
        # An internal Docker network suppresses host port publication. Use a
        # normal disposable bridge to exercise the same DNAT path as production.
        docker("network", "create", PREFIX)
        docker("volume", "create", PREFIX)
        try:
            ports = free_ports()
            fresh = PREFIX + "-fresh"
            start(fresh, ports, True, str(stub))
            verify(fresh, ports, True)
            docker("restart", fresh)
            verify(fresh, ports, True)
            docker("rm", "-f", fresh)
            containers.remove(fresh)

            # Recreate using the same persistent data and the old TCP-only layout.
            old = PREFIX + "-old"
            old_ports = free_ports()
            start(old, old_ports, False, str(stub))
            verify(old, old_ports, False)
            docker("exec", old, "sh", "-c", "printf preserved > /torrents/catalogue-test-marker")
            docker("stop", old)
            docker("rm", old)
            containers.remove(old)

            # The upgrade retains the daemon allocation and supplies new combined
            # FIRST_PORT/LAST_PORT allocations, as central reconciliation does.
            upgraded = PREFIX + "-upgraded"
            new_ports = [old_ports[0], *free_ports()[1:]]
            start(upgraded, new_ports, True, str(stub))
            verify(upgraded, new_ports, True)
            assert docker("exec", upgraded, "cat", "/torrents/catalogue-test-marker") == "preserved"
            docker("restart", upgraded)
            verify(upgraded, new_ports, True)
            print("PASS persistent volume retained across catalogue update", flush=True)
        finally:
            for name in containers:
                docker("rm", "-f", name, check=False)
            docker("volume", "rm", PREFIX, check=False)
            docker("network", "rm", PREFIX, check=False)


if __name__ == "__main__":
    main()
