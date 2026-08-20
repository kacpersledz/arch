# Poweroff reboots after resuming from hibernation

## Symptoms

On some systems, hibernation and resume succeed, but a later `poweroff` or shutdown reboots the machine instead of leaving it powered off.

The issue may be intermittent. A resumed session can sometimes have a working TPM and sometimes fail with:

```text
Failed to create TPM2 context: State not recoverable
```

## Confirm the issue

After an affected shutdown/reboot cycle, inspect the previous boot:

```bash
sudo journalctl -b -1 --no-pager | grep -Ei 'systemd-pcrphase|systemd-pcrextend|State not recoverable|Forcibly rebooting'
```

The relevant failure looks like:

```text
Failed to create TPM2 context: State not recoverable
systemd-pcrphase-sysinit.service: Failed with result 'exit-code'.
Forcibly rebooting: unit systemd-pcrphase-sysinit.service failed
```

`systemd-pcrphase.service` may fail as well.

## Why this happens

Wintarch configures `HibernateMode=shutdown` so the machine powers off after writing the hibernation image. On affected hardware or firmware, the TPM can become unavailable after resume.

During a later shutdown, systemd's PCR phase services try to access the TPM. Their default `FailureAction=reboot-force` can then turn the requested poweroff into a forced reboot.

This is not applied as a Wintarch-wide fix because the TPM failure appears to be hardware/firmware specific. The workaround below changes only systemd's response if either PCR phase unit fails; it does not fix the underlying TPM resume problem.

## Workaround

Apply this only after confirming the TPM/PCR failure above.

Create persistent systemd drop-ins for both affected units:

```bash
for u in systemd-pcrphase.service systemd-pcrphase-sysinit.service; do sudo mkdir -p "/etc/systemd/system/$u.d"; printf '[Unit]\nFailureAction=none\n' | sudo tee "/etc/systemd/system/$u.d/override.conf" >/dev/null; done; sudo systemctl daemon-reload
```

Verify the effective configuration:

```bash
for u in systemd-pcrphase.service systemd-pcrphase-sysinit.service; do echo "=== $u ==="; systemctl show "$u" -p FailureAction -p DropInPaths; done
```

Both units should report:

```text
FailureAction=none
```

The PCR phase services remain enabled and continue to run. This changes only what systemd does when one of them fails.

## Roll back

To restore systemd's default behavior:

```bash
sudo rm -rf /etc/systemd/system/systemd-pcrphase.service.d /etc/systemd/system/systemd-pcrphase-sysinit.service.d && sudo systemctl daemon-reload
```

## Upstream

A closely matching systemd issue is tracked at [systemd/systemd#39416](https://github.com/systemd/systemd/issues/39416).
