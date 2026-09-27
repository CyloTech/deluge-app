# Deluge combined torrent ports

Catalogue release `2.2.0-lt-2.0.10.0-1` reuses the published Deluge 2.2.0 image,
pinned by digest. It requires no image rebuild. The historical source checkout
does not reproduce that image; do not build this catalogue release from its
Dockerfile.

## Port mapping

| Index | Existing environment variable | Previous protocol | New protocol |
| --- | --- | --- | --- |
| 0 | `DAEMON_PORT` | TCP | TCP |
| 1 | `FIRST_PORT` | TCP | TCP and UDP |
| 2 | `LAST_PORT` | TCP | TCP and UDP |

The published startup script sets both ends of Deluge's listening range to
`FIRST_PORT`. The third allocation remains for compatibility with the existing
`LAST_PORT` template and older Deluge releases. No environment templates change.

Serverapi requests TCP allocations before combined allocations. Central port
templates sort by row ID. On update, central reconciliation retains the first
TCP allocation, removes the two surplus TCP rows and allocates two combined
ports. Those torrent port numbers may change. The image updates `listen_ports`
on fresh install, recreation with existing data, and restart.

`combined` produces separate TCP and UDP Docker bindings with identical host
and container port numbers. The daemon remains TCP only. Existing app slots,
resource limits, mounts, installation fields and older version port definitions
are preserved.

## Validation and publication

1. Run `python3 catalog/test-published-image.py` on the dedicated builder. This
   tests fresh install, restart and recreation with the same test volume, checks
   daemon/torrent TCP reachability, and requires a DHT ping response through the
   forwarded UDP torrent port. Test containers have an internal network and a
   stubbed installation callback.
2. Deliver this exact pushed Git commit to a separate checkout on the API host.
3. Run the deployed importer against `catalog/appbox.yml` with `--dry-run
   --import-version --app-id=68 --admin-only`. Inspect the result.
4. Import with the same arguments except `--dry-run`. Do not use `--set-default`:
   the guarded publication below preserves app-level fields exactly.
5. Execute `catalog/publish.sql` against the central database. It requires the
   reviewed baseline and imported candidate, checks resource and port template
   parity, writes customer release notes, and changes the default atomically.
6. Read back both version rows, app-level defaults, resource settings and notes.

The catalogue update does not update customer instances. Customers apply the
new port mappings through the normal Appbox version update action.
