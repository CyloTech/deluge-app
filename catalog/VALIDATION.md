# Publication record

- Catalogue app: `68` (Deluge).
- Previous default: version row `71`, `2.2.0-lt-2.0.10.0`.
- New default: version row `1336`, `2.2.0-lt-2.0.10.0-1`.
- Applied Git commit: `373f056e9608b5223483ea9f0af6f0c3fdaf59db`.
- Published image reused: `repo.cylo.net/deluge:2.2.0`.
- Verified amd64 manifest digest: `sha256:bd878dd1d131d9ce428519f98ebc3f8a9fd180f86a0cc5718ecac552dbf0747b`.

## Passed checks

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

## Catalogue readback

The supported importer created an admin-only candidate. The committed guarded
transaction then saved release notes, made the candidate public/default, and
updated the app defaults to one TCP plus two combined dynamic ports.

Independent PostgreSQL MCP readback confirmed `enabled=1`, `is_default=1`,
`admin_only=0`, non-empty customer release notes and exact resource parity with
the prior release. Before/after hashes matched for the app excluding intended
release fields, older versions excluding default/timestamp fields, environment
templates and installation fields. The old version's TCP definitions remain
unchanged. No customer instance update was performed.
