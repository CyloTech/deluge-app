-- Run after the supported AppsTask import with --admin-only (without --set-default).
-- Catalogue metadata only: no appinstance, appports or customer configuration writes.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $$
DECLARE
    baseline app_versions%ROWTYPE;
    candidate app_versions%ROWTYPE;
    application apps%ROWTYPE;
    changed integer;
    release_notes text := 'Adds UDP forwarding to the torrent ports for incoming uTP peers and DHT. Update Deluge from Appbox to apply the new port mappings. Assigned torrent port numbers may change; Deluge is configured automatically.';
BEGIN
    SELECT * INTO STRICT application FROM apps WHERE id = 68 FOR UPDATE;
    SELECT * INTO STRICT baseline FROM app_versions
      WHERE id = 71 AND app_id = 68 AND version = '2.2.0-lt-2.0.10.0' FOR UPDATE;
    SELECT * INTO STRICT candidate FROM app_versions
      WHERE app_id = 68 AND version = '2.2.0-lt-2.0.10.0-1' FOR UPDATE;

    IF application.display_name <> 'Deluge'
       OR application.version <> baseline.version
       OR application.tag <> '2.2.0'
       OR application."Image" <> 'deluge'
       OR application."TCPDynamicPorts" IS DISTINCT FROM 3
       OR COALESCE(application."CombinedDynamicPorts", 0) <> 0
       OR baseline.is_default IS DISTINCT FROM 1
       OR baseline.tcp_dynamic_ports IS DISTINCT FROM 3
       OR COALESCE(baseline.combined_dynamic_ports, 0) <> 0
       OR candidate.is_default IS DISTINCT FROM 0
       OR candidate.admin_only IS DISTINCT FROM 1
       OR candidate.enabled IS DISTINCT FROM 1
       OR candidate.tag <> '2.2.0'
       OR candidate.image <> 'deluge'
       OR candidate.installed_image_digest IS DISTINCT FROM
          'repo.cylo.net/deluge@sha256:bd878dd1d131d9ce428519f98ebc3f8a9fd180f86a0cc5718ecac552dbf0747b'
       OR candidate.tcp_dynamic_ports IS DISTINCT FROM 1
       OR candidate.combined_dynamic_ports IS DISTINCT FROM 2
       OR candidate.tcp_port_range IS NOT NULL
       OR candidate.udp_port_range IS NOT NULL
       OR candidate.combined_port_range IS NOT NULL
       OR COALESCE(candidate.udp_dynamic_ports, 0) <> 0
       OR (SELECT count(*) FROM app_versions WHERE app_id=68 AND is_default=1) <> 1
    THEN
        RAISE EXCEPTION 'Deluge catalogue prior state or imported candidate differs from the reviewed release';
    END IF;

    IF ROW(candidate.app_slots, candidate.memory, candidate.memory_swap,
           candidate.memory_reservation, candidate.cpus, candidate.min_memory,
           candidate.min_cpus, candidate.pids_limit, candidate.init,
           candidate.privileged, candidate.cap_add, candidate.cap_drop,
           candidate.custom_field_preinstall_description,
           candidate.custom_field_postinstall_description)
       IS DISTINCT FROM
       ROW(baseline.app_slots, baseline.memory, baseline.memory_swap,
           baseline.memory_reservation, baseline.cpus, baseline.min_memory,
           baseline.min_cpus, baseline.pids_limit, baseline.init,
           baseline.privileged, baseline.cap_add, baseline.cap_drop,
           baseline.custom_field_preinstall_description,
           baseline.custom_field_postinstall_description)
    THEN
        RAISE EXCEPTION 'Deluge resource or installation-description parity failed';
    END IF;

    IF (SELECT count(*) FROM appenvironmentvars WHERE app_id=68 AND version IS NULL
        AND template_type='instance'
        AND (ROW("Key", "Value") IN
             (ROW('DAEMON_PORT','%PORTS|0.EXTERNAL%'),
              ROW('FIRST_PORT','%PORTS|1.EXTERNAL%'),
              ROW('LAST_PORT','%PORTS|2.EXTERNAL%')))) <> 3
       OR EXISTS (SELECT 1 FROM appenvironmentvars WHERE app_id=68
                  AND version=candidate.version AND "Key" IN ('DAEMON_PORT','FIRST_PORT','LAST_PORT'))
    THEN
        RAISE EXCEPTION 'Deluge port environment templates differ from the reviewed mapping';
    END IF;

    UPDATE app_versions SET is_default=0, updated_at=CURRENT_TIMESTAMP WHERE id=baseline.id AND is_default=1;
    GET DIAGNOSTICS changed = ROW_COUNT;
    IF changed <> 1 THEN RAISE EXCEPTION 'Expected one previous Deluge default'; END IF;

    UPDATE app_versions SET changes=release_notes, admin_only=0, is_default=1,
      updated_at=CURRENT_TIMESTAMP WHERE id=candidate.id AND admin_only=1 AND is_default=0;
    GET DIAGNOSTICS changed = ROW_COUNT;
    IF changed <> 1 THEN RAISE EXCEPTION 'Expected one Deluge candidate'; END IF;

    UPDATE apps SET version=candidate.version, "TCPDynamicPorts"=1,
      "CombinedDynamicPorts"=2, updated_at=CURRENT_TIMESTAMP::text
      WHERE id=68 AND version=baseline.version;
    GET DIAGNOSTICS changed = ROW_COUNT;
    IF changed <> 1 THEN RAISE EXCEPTION 'Expected one Deluge app'; END IF;

    IF (SELECT count(*) FROM app_versions WHERE app_id=68 AND is_default=1) <> 1
       OR NOT EXISTS (SELECT 1 FROM app_versions WHERE id=candidate.id AND is_default=1
                      AND enabled=1 AND admin_only=0 AND changes=release_notes)
    THEN
        RAISE EXCEPTION 'Deluge publication postcondition failed';
    END IF;
    RAISE NOTICE 'Published Deluge catalogue version % (ID %); existing instances unchanged', candidate.version, candidate.id;
END $$;
COMMIT;
