# Digital garden

Fresh-install state for [Tend](https://github.com/archaic-java/tend), independent of the running
homelab. Read [the maintenance entry point](skills/maintain-digital-garden/SKILL.md).

`scripts/prepare.py` builds the complete seven-workload state from **reviewed public installation
inputs**. It requires resolved image fingerprints and explicit site values; it has no production
network defaults and rejects placeholder images. The assets match homelab commit
`8fc54492c6d75d9713061703c5a6667347e1481b`, with password-or-passkey `one_factor`, explicit
private-input delivery and flattened Grafana provisioning. Preparation performs no remote writes.

```sh
python3 scripts/prepare.py /path/to/reviewed-public-site.json /path/to/empty-prepared-state
python3 scripts/prepare.py --validate /path/to/empty-prepared-state
python3 scripts/test-prepare.py
```

Review the resulting `incus.xml`, public application files, `installation.json` and provenance
as one Git change, then place them at the repository root on the installation branch. Tend watches
that reviewed branch's eventual `main` commit. Do not hand-edit application settings after preparation.
The exact required public inputs and bootstrap order are documented in
[installation](skills/maintain-digital-garden/references/installation.md).

**No installation-specific site inputs have been supplied yet.** This PR therefore provides the
complete preparation recipe and assets, rather than inventing deployable production values. There
is no active `incus.xml` on main. Issue #2 remains open until the prepared installation state is
reviewed. Draft illustrative PR #1 contains an empty deployment and placeholder examples; it is
not this installation and should be superseded rather than treated as deployed state.

Never commit real users/password hashes, SMTP passwords, client private keys or generated secrets.
Private users and Incus metrics credentials are operator-owned volumes; Tend generates stable
application/session/OIDC credentials on its own retained state volume. No old application data or
credentials are adopted. Production host/GPU/public-ACME commissioning remains a separate gate.
