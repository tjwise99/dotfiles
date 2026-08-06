# Repo Health Audit — <REPO NAME>

- **Date**: <YYYY-MM-DD>
- **Commit**: <short sha>
- **Auditor**: repo-health skill (Claude Code)

## Profile & threat model
<5–8 line profile from Phase 0: ecosystems, containerization, CI, deploy model/exposure, fork/visibility.>

**Threat model**: <one line — what an attacker would target and what's out of scope for this deploy.>

## Scan coverage
| Domain | Tools run | Not run (tool absent) |
|--------|-----------|------------------------|
| Dependencies | | |
| Supply chain / CI | | |
| Container | | |
| Secrets | | |
| SAST / code | | |
| GitHub config | | |
| Runtime | | |

## Findings (triaged)
| # | Domain | Finding | Severity | Exploitability | Effort | Status |
|---|--------|---------|----------|----------------|--------|--------|
<!-- Status: open / accepted-risk / false-positive / fixed. Carry # across runs so drift is trackable. -->

## Remediation plan
### Quick wins (<30 min)
- [ ] **#<n>** — <change> · verify: `<cmd/check>`

### Medium
- [ ] **#<n>** — <change> · verify: `<cmd/check>`

### Projects
- [ ] **#<n>** — <change> · verify: `<cmd/check>`

## Accepted risks / out of scope
- **#<n>** — <finding> — <why it's accepted given the threat model.>

## Change since last audit
<!-- On re-runs: newly-introduced / fixed / still-open / regressed. Omit on first run. -->
