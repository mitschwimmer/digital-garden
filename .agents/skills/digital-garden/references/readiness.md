# Wait for guest readiness

## Scope and inputs

Wait for a healthy NixOS system and private IPv4 address before application
checks. This procedure observes the guest; it does not change infrastructure
or prove application readiness.

Run on the fish workstation with `GARDEN_GUEST` and `GARDEN_PROJECT` set by the
service procedure. Incus reporting RUNNING does not mean the guest system bus or DHCP is
ready. Run each block separately; do not continue after a failed check. Use native
workstation `timeout`, `seq` and `sleep` from coreutils.

## Apply the change

Poll up to 30 times, with a five-second limit per call and two seconds between
attempts (at most approximately 210 seconds). Temporary early-boot bus errors are
suppressed only during this bounded check. A degraded guest never passes it.

```fish
set -l GARDEN_READY 0
for attempt in (seq 1 30)
    if timeout 5s incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -T -- env TERM=xterm systemctl is-system-running --quiet 2>/dev/null
        set GARDEN_READY 1
        break
    end
    sleep 2
end
test "$GARDEN_READY" = 1
```

The final `test` must exit 0 (`echo $status` immediately afterward). If it exits 1,
stop and collect the [diagnostics](#resume-and-rollback). Do not extend the wait indefinitely.

## Check the result

```fish
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -T -- env TERM=xterm systemctl is-system-running
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -T -- env TERM=xterm systemctl --failed --no-pager
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -T -- ip -4 address show eth0
```

Expect `running`, zero failed units and a global IPv4 address on eth0. System
readiness does not prove network or application readiness: repeat the affected service's
DNS, health, external and persistence checks after restart.

## Resume and rollback

```fish
incus info "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT"
incus console "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" --show-log
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -T -- ps -p 1 -o pid,comm,args
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -T -- env TERM=xterm systemctl --failed --no-pager
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -T -- journalctl -b -p warning --no-pager -n 80
```

A missing bus after the bounded wait needs boot/PID-1 diagnosis, not a new image
or deletion of state. `TERM=xterm`, noninteractive exec and `--no-pager` avoid
unknown workstation terminal types such as `xterm-ghostty` in the minimal guest.
Review application logs locally before sharing; do not post credentials or tokens.

If OpenTofu reports an address changing to null immediately after restart, first
wait for readiness, inspect the actual address and rerun the plan. Do not apply
that output-only plan or add `ignore_changes` merely to hide transient readiness.

Sources: [Incus exec](https://linuxcontainers.org/incus/docs/main/reference/manpages/incus/exec/)
and [systemctl](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html).
