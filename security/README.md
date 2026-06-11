# Security

Host-hardening utilities for Windows 11. Currently: a declarative, reversible Microsoft Defender
hardening script for hosts where Defender is the **sole** resident antivirus.

## Scripts

| Script | Purpose |
|--------|---------|
| `Harden-Defender.ps1` | Applies an idempotent, staged (audit → enforce) hardened Defender configuration. Source of truth for the host's Defender posture. |
| `Defender-Hardening.Helpers.ps1` | Pure helper functions (ASR catalog, desired-state, promotion resolution) dot-sourced by the script and unit-tested in CI. Not run directly. |

---

## Harden-Defender.ps1

The script is the source of truth for the host's Defender posture: re-runnable, idempotent
(it converges to the declared desired state — it never accretes duplicate config), and reversible.
It replaces GUI tools like ConfigureDefender / DefenderUI.

It is **staged on purpose**. These hosts run WSL2, VMware, Tailscale (Hetzner exit node),
SMB-over-Tailscale, and self-built unsigned binaries — anything that breaks child-process spawning
or LAN/SMB/Tailscale traffic is high-risk, so the disruptive controls default to *audit* until you've
reviewed their impact and explicitly promoted them.

### Requirements

- Windows 11, run from an **elevated** PowerShell session (`#Requires -RunAsAdministrator`).
- The built-in Defender PowerShell module (`Get-MpPreference`). No external modules, no network calls.

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Mode Audit\|Enforce` | `Audit` | `Audit`: all ASR rules + CFA observe-only (baseline still applied). `Enforce`: Phase 1 ASR blocks; Phase 2 + CFA stay in audit unless promoted. |
| `-PromoteRules <names>` | — | Phase 2 ASR rules to promote to block (Enforce only). GUID, canonical name, or short key. |
| `-EnableControlledFolderAccess` | off | In Enforce, set CFA to block. Ignored in Audit. |
| `-MinimizeTelemetry` | off | Drop `MAPSReporting` from Advanced to Basic. |
| `-EnableLSAProtection` | off | Enable LSA Protection (RunAsPPL). Reboot required. |
| `-LSAProtectionUefiLock` | off | With the above, use `RunAsPPL=1` (UEFI lock) instead of `2` (reversible). |
| `-ExclusionPath <paths>` | empty | Defender path exclusions (dev build dirs). |
| `-ExclusionProcess <names>` | empty | Defender process exclusions (e.g. self-built binaries). |
| `-Rollback <backup.json>` | — | Restore from a prior backup and exit. |
| `-OutputDirectory <dir>` | `%ProgramData%\DefenderHardening` | Where logs + backups go. |
| `-Transcript` | off | Also wrap the run in `Start-Transcript`. |
| `-WhatIf` | — | Show every change without making it. |

### What it changes

- **Cloud / baseline** (`Set-MpPreference`, applied in both modes): `PUAProtection=Enabled`,
  `MAPSReporting=Advanced`, `CloudBlockLevel=High`, `CloudExtendedTimeout=50`,
  `SubmitSamplesConsent=NeverSend`, `EnableNetworkProtection=Enabled`.
  - `SubmitSamplesConsent=NeverSend` is a telemetry/privacy control and prevents auto-upload of
    self-built binaries. **Tradeoff:** it disables Block-at-First-Sight on never-before-seen files.
  - Network Protection is reputation-based (malicious domains/IPs/phishing). It does **not** block
    private LAN, SMB, or Tailscale traffic — it is unrelated to the out-of-scope LOLBin firewall idea.
- **ASR rules** (staged — see table below), applied as the full desired set (replace semantics).
- **Controlled Folder Access** — audit by default; blocks only with `-Mode Enforce -EnableControlledFolderAccess`.
- **Exclusions** — only what you pass (default none).
- **LSA Protection (RunAsPPL)** — only with `-EnableLSAProtection`. The one change outside Defender config.

### What it only reports (never changes)

- **Tamper Protection** — cannot be set by script by design; warns if off (while off/managed elsewhere,
  some `Set-MpPreference` changes may not persist — the script flags any that don't read back).
- **LSA Protection** current state.
- **HVCI / Memory Integrity** and **Credential Guard** — reported, deliberately not enabled (driver-compat
  risk with VMware + kernel workloads).
- **Exploit Protection** (system) — reported; system mitigations are mostly default-on. Per-app tuning is
  intentionally not automated here.

### ASR rules

GUIDs are resolved from the [Microsoft Learn ASR rules reference](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference).
Phases: **1** = blocks in Enforce (low disruption) · **2** = the reviewed set, promote after the first
audit cycle · **3** = extended coverage, promote opportunistically as audit data accumulates. Phases 2
and 3 behave identically in the engine (audit unless promoted); the split is rollout guidance.

| Phase | Rule | Short key | Enforce | Note |
|-------|------|-----------|---------|------|
| 1 | Block credential stealing from LSASS | — | **Block** | |
| 1 | Block abuse of exploited vulnerable signed drivers | — | **Block** | |
| 1 | Block persistence through WMI event subscription | — | **Block** | |
| 2 | Block all Office applications from creating child processes | `BlockOfficeChildProcesses` | Audit → promote | |
| 2 | Block execution of potentially obfuscated scripts | `BlockObfuscatedScripts` | Audit → promote | can FP on legit minified/packed scripts — review first |
| 2 | Block executable content from email client and webmail | `BlockEmailExecutableContent` | Audit → promote | |
| 2 | Block process creations originating from PSExec and WMI commands | `BlockPsexecWmiProcessCreation` | Audit → promote | |
| 3 | Block Adobe Reader from creating child processes | `BlockAdobeReaderChildProcesses` | Audit → promote | inert without Reader |
| 3 | Block JavaScript or VBScript from launching downloaded executable content | `BlockJsVbsLaunchingExecutables` | Audit → promote | WSH-based; node/npm unaffected |
| 3 | Block Office applications from creating executable content | `BlockOfficeExecutableContent` | Audit → promote | |
| 3 | Block Office applications from injecting code into other processes | `BlockOfficeCodeInjection` | Audit → promote | |
| 3 | Block Office communication application from creating child processes | `BlockOfficeCommsChildProcesses` | Audit → promote | Outlook |
| 3 | Block rebooting machine in Safe Mode | `BlockSafeModeReboot` | Audit → promote | anti-ransomware, ~zero dev impact |
| 3 | Block untrusted and unsigned processes that run from USB | `BlockUntrustedUsbProcesses` | Audit → promote | only bites if you run unsigned tools off USB |
| 3 | Block use of copied or impersonated system tools | `BlockImpersonatedSystemTools` | Audit → promote | |
| 3 | Block Win32 API calls from Office macros | `BlockOfficeMacroWin32Api` | Audit → promote | inert without macros |
| 3 | Use advanced protection against ransomware | `AdvancedRansomwareProtection` | Audit → promote ⚠ | blocks **unknown-reputation** files — promote only after `-ExclusionPath` covers self-built binary output dirs |

#### Permanently excluded rules (not in the catalog)

| Rule | Why excluded |
|------|--------------|
| Block executable files from running unless they meet a prevalence, age, or trusted list criterion (`01443614-cd74-433a-b99e-2ecdc07bfc25`) | Allowlisting by another name — blocks `endstate.exe`-class self-built binaries by design. Same rationale as the WDAC / Smart App Control exclusion. |
| Block Webshell creation for Servers (`a8f5898e-1dc8-49a9-9878-85004b8a61e6`) | Exchange servers only; not applicable to a client host. |

### Usage

```powershell
# 1. Audit run — applies baseline, puts all ASR rules + CFA in audit, writes a backup.
.\Harden-Defender.ps1

# Dry run of an enforce pass — shows every change, makes none.
.\Harden-Defender.ps1 -WhatIf -Mode Enforce

# 2. Enforce Phase 1 (Phase 2 + CFA still audited).
.\Harden-Defender.ps1 -Mode Enforce

# 3. Promote reviewed Phase 2 rules to block, per-rule.
.\Harden-Defender.ps1 -Mode Enforce -PromoteRules BlockObfuscatedScripts,BlockPsexecWmiProcessCreation

# Full hardening with CFA blocking and LSA Protection (reboot required for LSA).
.\Harden-Defender.ps1 -Mode Enforce -EnableControlledFolderAccess -EnableLSAProtection

# Dev exclusions (reduce protection — use only trusted, frequently-rebuilt locations).
.\Harden-Defender.ps1 -Mode Enforce -ExclusionPath 'C:\src\endstate\target\release' -ExclusionProcess 'endstate.exe'
```

### Rollout runbook (audit → enforce)

Every command below is a single line, run from an elevated PowerShell in `security\`.

1. **Manual prerequisite — Tamper Protection.** Enable it by hand (script-setting is blocked by design;
   this script only warns): Windows Security → Virus & threat protection → Manage settings → Tamper
   Protection **On**. While there, confirm SmartScreen is on (App & browser control).
2. **Audit run.** Baseline applied; all 17 ASR rules + CFA observe-only; backup written:
   ```powershell
   .\Harden-Defender.ps1
   ```
   Re-run it once — the second run should report everything "unchanged" (idempotency check).
3. **Soak 1–2 weeks** of normal work (WSL2, VMware, Tailscale/SMB, builds), then **review events**
   (**ID 1122 = audited**, **ID 1121 = blocked**, 5007 = config change):
   ```powershell
   Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' -MaxEvents 500 | Where-Object { $_.Id -in 1121,1122 } | Format-Table TimeCreated,Id,Message -Wrap
   ```
   In Defender for Endpoint, the `DeviceEvents` table (`Asr*Audited` / `Asr*Blocked` action types).
4. **Optionally validate with [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team)** test
   cases mapped to the enabled rules — confirm audit events fire, check for false-blocks on dev tooling.
5. **Enforce Phase 1** (Phase 2/3 + CFA remain audited):
   ```powershell
   .\Harden-Defender.ps1 -Mode Enforce
   ```
6. **Promote per-rule** once a rule's audit events look clean — Phase 2 first, Phase 3 opportunistically.
   Promotions are a declarative list: pass every promoted rule each run (the script applies the full
   desired set, so the list in the command IS the promoted set):
   ```powershell
   .\Harden-Defender.ps1 -Mode Enforce -PromoteRules BlockObfuscatedScripts,BlockPsexecWmiProcessCreation,BlockSafeModeReboot,BlockImpersonatedSystemTools
   ```
   ⚠ Promote `AdvancedRansomwareProtection` only after `-ExclusionPath` covers your build output dirs.
7. Enable **CFA** / **LSA Protection** when ready (both have higher friction; LSA needs a reboot):
   ```powershell
   .\Harden-Defender.ps1 -Mode Enforce -PromoteRules <your-list> -EnableControlledFolderAccess -EnableLSAProtection
   ```
8. **Optional extra (manual):** run Defender's content processes sandboxed —
   `setx /M MP_FORCE_USE_SANDBOX 1` then reboot. Low interference; revert with the value `0`.

### Rollback

Every apply run writes a timestamped backup to `…\DefenderHardening\backups\Defender-Backup_<stamp>.json`
(plus a `Get-MpPreference` Clixml snapshot). To restore:

```powershell
.\Harden-Defender.ps1 -Rollback 'C:\ProgramData\DefenderHardening\backups\Defender-Backup_20260607-101500.json'
```

Rollback restores the baseline preferences, CFA, and prior ASR actions (disabling rules this script added
that weren't present before), removes only the exclusions added after the backup, and restores `RunAsPPL`.
LSA changes need a reboot. Manual restore is also possible from the Clixml snapshot via `Set-MpPreference`.

### Logs and backups

Written under `-OutputDirectory` (default `%ProgramData%\DefenderHardening`): `logs\Harden-Defender_<stamp>.log`
(structured before→after of every changed setting) and `backups\…`. Nothing is written into the repo.

### Out of scope (deliberately not implemented)

| Excluded | Why |
|----------|-----|
| WDAC / Smart App Control | Allowlisting blocks new/self-built binaries (`endstate.exe`-class) by design; SAC is clean-install-only. |
| Blanket outbound LOLBin firewall rules | Reintroduces the silent LAN/SMB/Tailscale blocking that motivated leaving the paid suite. |
| HVCI / Memory Integrity (VBS) | Driver-compat risk with VMware + kernel workloads. Reported only. |
| `-Disable*` real-time toggles (behavior monitoring, script/IOAV/archive/email scanning) | Defaults are correct; leave them. |

---

## Testing

Pure logic is unit-tested (no elevation, no host changes) via the repo's Pester v5 harness:

```powershell
.\tests\run-tests.ps1
```

See `tests/unit/Harden-Defender.Tests.ps1` (catalog integrity incl. a GUID drift-guard, desired-state per
mode, promotion resolution, action formatting). The same tests run in CI on push/PR.

---

## Companion: handling false positives on self-built binaries

For `endstate.exe`-class detections on your own unsigned builds — this is false-positive **correction**,
not evasion:

- **Code signing is the real fix.** An EV cert gives near-instant SmartScreen/Defender reputation.
- **Do not pack or obfuscate** your binaries — packing is the #1 trigger for ML false positives.
- **Submit to Microsoft WDSI** at <https://www.microsoft.com/wdsi/filesubmission> as
  "Software developer – false positive" for a cloud-level correction that helps every host.
- **Interim local measure:** add a Defender exclusion (`-ExclusionPath` / `-ExclusionProcess`) and
  clear the Mark-of-the-Web with `Unblock-File` on the built artifact.

---

## References

- [Microsoft Learn — `Set-MpPreference`](https://learn.microsoft.com/en-us/powershell/module/defender/set-mppreference)
- [Microsoft Learn — Attack surface reduction rules reference](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference)
- Rationale / full comparison: KB note
  `Knowledge Base/Notes/Research/Personal/windows-defender-hardening-av-posture-and-config-surface.md`
