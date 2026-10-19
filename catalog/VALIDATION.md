# Publication records

## 2.2.0-lt-2.0.10.0-3

- Catalogue app: `68` (Deluge).
- Previous default: version row `1417`, `2.2.0-lt-2.0.10.0-2`.
- New default: version row `1424`, `2.2.0-lt-2.0.10.0-3`.
- Image source commit: `5f54109e28ab1ad90599b541c606aabb9222c668`.
- Catalogue commit applied: `1790d3441c86b28cd6a99cbc9ba859809f779137`.
- Image: `repo.cylo.net/deluge:2.2.0-lt-2.0.10.0-3`, index
  `sha256:1633d610348af20b55c1ac497aa4221c82102412e9d1dd74d8d44eb76b088a03`,
  amd64 manifest `sha256:33b1fb5c4d511645db551bdf6486033b9eca6839b70c021d01f52132631a158c`.

### Passed checks

`catalog/release-gate.py` on the dedicated builder, before push: package
versions; fresh install and restart; update from the `-2` image on the same test
volume after setting non-template Deluge and ltConfig preferences, with the
preferences, test data, ports, Web UI and 65535 open-files limits checked after
the update and after a further restart; registry precondition.

The first gate run (from `b3adb13`) failed before push: its preference set
disabled DHT, which correctly stopped Deluge answering the gate's DHT ping.
`5f54109` uses a different preference; nothing from the failed run was pushed.

### Catalogue readback

The deployed importer (as `nginx`) passed a dry run and created admin-only
candidate `1424`. App row, other versions, environment templates and custom
fields were unchanged by the import. `publish.sql` then saved the release notes,
made `1424` public and default, and set the app-level version and tag. Readback
confirmed one default version, exact notes, resource parity with `1417`, and
unchanged hashes for older versions (excluding default/timestamp), environment
templates and custom fields. No customer instance was updated.

## 2.2.0-lt-2.0.10.0-2

- Catalogue app: `68` (Deluge).
- Previous default: version row `1336`, `2.2.0-lt-2.0.10.0-1`.
- New default: version row `1417`, `2.2.0-lt-2.0.10.0-2`.
- Image source commit: `5cd6fb06c8ed5195c533de90bb0df163aece5cac`.
- Catalogue commit applied: `6401b29646a99b4755b842f85cb0f852b698c6fc`.
- Image: `repo.cylo.net/deluge:2.2.0-lt-2.0.10.0-2`, index
  `sha256:f8cf06772ec61eddff4fa8ae0d1ae9eebe5c7755ef6cbc280330bf48f7287c10`,
  amd64 manifest `sha256:3599a7b253355610cc97f8e033bc39b164e0ef638633205c4483ad9b0526273a`.

### Passed checks

`catalog/release-gate.py` on the dedicated builder, before push:

- Deluge 2.2.0 with libtorrent 2.0.10 in the built image.
- Fresh install, restart, and update from the previous image on the same test
  volume: daemon and torrent TCP reachable, DHT ping answered on the UDP torrent
  port, Web UI returned 200, test data kept across the update.
- Open-files soft limits 65535 for both `deluged` and `deluge-web` in every new
  container. The previous image showed `deluge-web` at 1024 under the same
  container ulimit (65535:65535), reproducing the fault.
- Registry readable; the new tag was absent before push.

### Catalogue readback

The deployed importer (run as the `nginx` user, which can read the API's
constants) passed a dry run and created admin-only candidate `1417`. The app
row, other versions, environment templates and custom fields were byte-identical
before and after the import. `publish.sql` then saved the release notes, made
`1417` public and default, and set the app-level version and tag.

Readback confirmed `enabled=1`, `is_default=1`, `admin_only=0`, exact release
notes, one default version, resource parity with `1336`, and unchanged hashes
for older versions (excluding default/timestamp), environment templates and
custom fields. The app-level `nofile` ulimit (65535:65535) applies to all
versions. No customer instance was updated.

## 2.2.0-lt-2.0.10.0-1

- Catalogue app: `68` (Deluge).
- Previous default: version row `71`, `2.2.0-lt-2.0.10.0`.
- New default: version row `1336`, `2.2.0-lt-2.0.10.0-1`.
- Applied Git commit: `373f056e9608b5223483ea9f0af6f0c3fdaf59db`.
- Published image reused: `repo.cylo.net/deluge:2.2.0`.
- Verified amd64 manifest digest: `sha256:bd878dd1d131d9ce428519f98ebc3f8a9fd180f86a0cc5718ecac552dbf0747b`.

### Passed checks

- Deployed `AppsTask.php` importer dry run.
- Existing central port reconciliation tests: 53 tests, 170 assertions.
- Published image fresh install with one TCP and two combined allocations.
- Restart with the same allocation.
- Recreation with the previous TCP-only layout and existing test data.
- Update from that layout to combined torrent ports using the same test volume.
- Restart after update.
- Correct `daemon_port`, fixed `listen_ports`, and Docker host/container bindings.
- TCP connections to the daemon and torrent listener.
- Actual DHT ping replies through the forwarded UDP torrent port on fresh install,
  restart and update.
- Test data marker retained across recreation/update.
- Builder test containers, network and volume removed by the test runner.

The first test attempt used an internal-only network, which suppresses Docker
host-port publication. The second attempt needed to wait for Supervisor to mark
its processes RUNNING after sockets opened. Both test issues were corrected;
the final run passed every check above.

### Catalogue readback

The supported importer created an admin-only candidate. The committed guarded
transaction then saved release notes, made the candidate public/default, and
updated the app defaults to one TCP plus two combined dynamic ports.

Independent PostgreSQL MCP readback confirmed `enabled=1`, `is_default=1`,
`admin_only=0`, non-empty customer release notes and exact resource parity with
the prior release. Before/after hashes matched for the app excluding intended
release fields, older versions excluding default/timestamp fields, environment
templates and installation fields. The old version's TCP definitions remain
unchanged. No customer instance update was performed.
