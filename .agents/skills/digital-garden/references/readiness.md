# Bound guest readiness checks

Read the chosen root's target.json and `tofu output -json deployment`; compare
project, instance, remote and metadata before using native diagnostic commands.
Never carry a guest/config selection from another terminal task.

For example, for identity (replace YOUR_REMOTE with its applied remote):

```fish
incus info YOUR_REMOTE:identity --project identity
incus config get YOUR_REMOTE:identity user.garden.system --project identity
incus exec YOUR_REMOTE:identity --project identity -- timeout 90 systemctl is-system-running --wait
incus exec YOUR_REMOTE:identity --project identity -- mountpoint /var/lib/kanidm
incus exec YOUR_REMOTE:identity --project identity -- mountpoint /var/lib/acme
incus exec YOUR_REMOTE:identity --project identity -- mountpoint /var/lib/garden-secrets
```

Require identity metadata to equal identity, all mounts present and systemd
running. If degraded, inspect `systemctl --failed` and the affected journal;
never wait indefinitely or continue because the container merely says RUNNING.
Use each other root's exact target/mounts for its checks. A seed has no service
units yet; full configuration needs separate deployment.

Check DNS and backend reachability from the actual caller. After service
deployment use that reference's bounded health checks. On missing mounts repair
Incus devices before services can write to the disposable root. Stop on errors;
do not enable privilege, remove conditions or disable firewalls to force progress.
