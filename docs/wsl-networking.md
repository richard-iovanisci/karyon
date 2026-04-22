# WSL2 Networking: Mirrored Mode, NAT Mode, and the Migration Procedure

## What Is mirrored Mode and Why It Breaks Docker Custom Networks

WSL2 supports two networking modes: **NAT** (the default prior to Windows 11 22H2) and
**mirrored** (introduced in Windows 11 22H2). In mirrored mode, Windows host NICs are mirrored
directly into the WSL2 VM — the WSL2 instance shares the same IP addresses and network interfaces
as the Windows host.

This breaks Docker custom networks (such as the `k8s-net` bridge network used by this project).
Docker custom bridge networks rely on network namespace isolation: containers get their own IP
addresses on an isolated L2 segment, separated from the host by NAT. When WSL2 mirrors the
Windows host NICs into the VM, the network address space that Docker expects to own for its
bridge interface overlaps with the host address space. Docker containers on custom networks
(created with `docker network create`) cannot reliably communicate with each other or resolve
each other by DNS hostname.

This is a known upstream issue tracked at `moby/moby#48201`. The symptom is: `docker network
create k8s-net` succeeds, but containers on that network fail to reach each other by IP or by
Docker DNS name. `k3d` clusters placed on this network become unreachable across nodes.

**v1 of this project requires NAT mode.** Mirrored mode is not supported and will cause
`scripts/preflight.sh` to exit 1 with an actionable error message.

---

## v1 Mandate: NAT Mode

This project pins `networkingMode=NAT` explicitly in `config/wslconfig` (the template for
`%USERPROFILE%\.wslconfig`). The decision is recorded as D-01 and D-03 in
`.planning/phases/01-host-foundation/01-CONTEXT.md`.

**NAT mode is the only supported networking posture for v1.** The commented-out mirrored line
in `config/wslconfig` exists to make the decision visible — do not uncomment it without reading
this document and understanding the consequences.

If you are on a system where mirrored mode was explicitly set, `scripts/preflight.sh` will
detect it (see detection section below) and refuse to continue until you migrate back to NAT.

---

## How Preflight Detects Mirrored Mode

`scripts/preflight.sh` (PRE-03) uses the **IP-subnet overlap heuristic** (D-02) to detect
mirrored networking without requiring the Windows host to expose its networking mode to WSL:

1. **Enumerate non-loopback WSL interfaces:** `ip -4 -o addr show` — collect all IPv4 CIDRs
   assigned to WSL network interfaces (excluding `lo`).

2. **Determine the Windows host IP:** Try the default route gateway first
   (`ip -4 route show default | awk '/via/ {print $3}'`). Fall back to the first `nameserver`
   line in `/etc/resolv.conf` (valid when `generateResolvConf=true` in `wsl.conf`).

3. **Test for overlap:** Use `ip_in_cidr()` (pure bash arithmetic, no external tools) to test
   whether the Windows host IP falls inside any WSL interface CIDR.

4. **Verdict:** If the Windows host IP is inside a WSL interface CIDR, the WSL VM and the
   Windows host share an address space — which is the defining characteristic of mirrored mode.
   Preflight calls `fail()` with a pointer to this document.

**Known false-positive:** On unusual home networks where both the Windows host and the WSL VM
happen to land in the same subnet organically (e.g., both in `192.168.1.x` under a home router),
this heuristic may fire even in NAT mode. The remediation is the same: set `networkingMode=NAT`
explicitly in `%USERPROFILE%\.wslconfig` and run `wsl --shutdown`. An explicit NAT setting
overrides the heuristic's concern.

The implementation of `ip_in_cidr()` lives in `scripts/lib/preflight-lib.sh` (Section B).

---

## Migration: mirrored to NAT (30-second fix)

Follow these five steps exactly. Do not skip the wait in step 3 — the Hyper-V VM must fully
stop before WSL will pick up the new configuration.

**Step 1:** Edit `%USERPROFILE%\.wslconfig` in a text editor (Notepad, VS Code, etc.).
Set or add the following line in the `[wsl2]` section:

```ini
networkingMode=NAT
```

You can use the template at `config/wslconfig` in this repository as a reference.
Make sure there is no uncommented `networkingMode=mirrored` line — comment it out or remove it.

**Step 2:** Open PowerShell as a normal user (no Administrator required) and run:

```powershell
wsl --shutdown
```

**Step 3:** Wait at least **8 seconds**. The Hyper-V virtual machine that backs WSL2 must
fully stop. The 8-second delay is the documented Hyper-V VM shutdown timeout. Opening WSL
before this completes may reuse the old configuration.

**Step 4:** Open a new WSL terminal (start Ubuntu from the Start menu, or run `wsl` in
PowerShell).

**Step 5:** Verify the new networking mode:

```bash
ip addr show eth0
```

The IP address should be in the `172.x.x.x` range (typical for WSL2 NAT mode). If you see
a `192.168.x.x` or `10.x.x.x` address that matches your Windows host's LAN IP exactly,
the migration did not take effect — repeat from step 1 and confirm `%USERPROFILE%\.wslconfig`
was saved correctly.

You can also re-run `scripts/preflight.sh` — it will pass PRE-03 once NAT mode is active.

---

## Belt-and-Suspenders: Windows Task Scheduler hwclock Hook (Optional)

WSL2 is backed by a Hyper-V virtual machine. When Windows suspends or hibernates, the Hyper-V
VM is saved to disk and restored on resume. This save/restore cycle does not reliably trigger
the guest OS's `suspend.target` / `sleep.target` systemd units — the VM resumes as if time
never passed, but the hardware clock reflects the actual elapsed time.

This project ships a systemd unit at `config/hwclock-resume.service` that runs
`/sbin/hwclock --hctosys` (sync hardware clock to system clock) triggered by systemd's
`suspend.target`. `scripts/install-docker.sh` installs and enables this unit. It provides a
best-effort fix for the Linux-side clock skew.

**However**, because WSL2's Hyper-V save/restore does not reliably trigger `suspend.target`
inside the VM, the systemd unit may not fire on every resume. A more reliable (but optional)
alternative is a **Windows Task Scheduler task** triggered by a Windows resume event:

1. Open **Task Scheduler** on Windows.
2. Create a new task triggered by **Event ID 107** from the `Microsoft-Windows-Kernel-Power`
   source (this event fires when Windows resumes from sleep).
3. Set the action to run: `wsl.exe -u root sh -c "hwclock -s"`
4. Enable the task.

This runs `hwclock -s` inside WSL immediately after Windows resumes, before any user session
starts. It is more reliable than the systemd unit because it executes from the Windows side,
bypassing the Hyper-V VM lifecycle uncertainty. The trade-off is that it requires Windows-side
setup and is not automated by this project's install scripts.

Both mechanisms are independent and complementary — having both provides the best coverage.

---

## PRE-14 Bridge Probe Note

PRE-14 is the only preflight section that mutates Docker state. It creates ephemeral Docker
resources (a dedicated network `preflight-pre14-net` and two probe containers
`preflight-pre14-a`, `preflight-pre14-b`) to verify that containers on a custom Docker
network can reach each other by DNS hostname — the same connectivity model used by `k3d`
clusters on `k8s-net`.

All mutations are ephemeral and trap-cleaned:

- PRE-14 runs inside a subshell with `trap _pre14_cleanup EXIT`.
- The cleanup function removes all `preflight-pre14-*` containers and the `preflight-pre14-net`
  network before exit, whether the probe succeeded, failed, or was interrupted by SIGINT.
- A pre-check removes any stale `preflight-pre14-*` resources from crashed prior runs before
  starting the probe.
- After cleanup, a post-check warns (not fails) if any `preflight-pre14-*` resources remain.

`scripts/preflight.sh` is read-only with respect to persistent host state. PRE-14 ephemeral
Docker resources are the sole exception — and they are trap-cleaned before the section exits.
