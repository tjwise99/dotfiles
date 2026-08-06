---
name: repo-health
description: >-
  Repeatable cybersecurity + best-practices health audit for ANY git repo. Runs a phased
  sweep (dependencies, supply-chain/CI, container, secrets, SAST, GitHub config, runtime
  hardening), pauses for a collaborative triage checkpoint, and ends with a prioritized,
  actionable remediation plan. Invoke when the user wants to "audit", "harden", "fortify",
  "security review", "check the health of", or "find gaps in" a repository or its build/deploy
  pipeline. Repo-agnostic — works outside this project.
---

# Repo Health Audit

A repeatable, collaborative flow for interrogating a repository's security and engineering-hygiene
posture. The deliverable of every run is a **prioritized, actionable remediation plan** — not a raw
dump of scanner output.

Run the phases **in order**. Phase 2 is a hard stop for human input; do not skip it. The audit is
**read-only** — Phases 0–3 gather and reason, they never apply fixes. Remediation happens only after
the plan is agreed, as separate work.

## Operating rules (read first)
- **Target**: default to the current repo (`.`). If the user names a path or a GitHub repo, audit that.
- **Run what's available, guide the rest.** Probe for each scanner (`command -v <tool>`); run the ones
  present. For a missing tool, record the check as *"not run — `<tool>` absent"*, note the one-liner to
  enable it, and carry that into the plan as a recommendation. **Do not install tools** unless the user
  asks in this session.
- **Never exfiltrate or print secrets.** Redact any matched secret to a fingerprint (first/last 4 chars +
  length). Keep all scans local — no uploading repo contents to third-party services.
- **Tune to the threat model.** A self-hosted LAN appliance with no untrusted input (like MagicMirror)
  earns different severities than a public-facing SaaS. Establish the model in Phase 0 and weight findings
  by it in Phase 2.
- **Detailed per-domain checks + exact commands live in [`references/domains.md`](references/domains.md).**
  Load it when running Phase 1.

---

## Phase 0 — Scope & inventory  *(fast, automated)*
Build the profile that decides which checks apply. Determine:
- **Ecosystems & package managers** — which of `package.json` / `requirements.txt` / `go.mod` /
  `Cargo.toml` / `pom.xml` / `Gemfile` etc. exist; which lockfiles are present.
- **Containerization** — `Dockerfile`(s), `compose*.yml`, k8s manifests.
- **CI system** — `.github/workflows/`, `.gitlab-ci.yml`, etc.
- **Deploy model & exposure** — how/where it runs, what network surface it exposes, what untrusted input
  it processes. Ask the user if it isn't obvious from the repo.
- **Repo provenance** — is it a fork? public or private? (via GitHub MCP / `git remote`).

Output a short **Profile** block (5–8 lines) and a one-line **threat-model** statement. Confirm the threat
model with the user if you had to guess.

## Phase 1 — Recon  *(read-only, grouped by domain)*
Work the domains in `references/domains.md`, skipping those the Phase 0 profile rules out. For each check,
record: **status** (pass / finding / not-run), **evidence** (the command output or file:line), and a
**one-line finding** where relevant. Domains:

1. **Dependencies & lockfile** — audit CVEs, outdated majors, lockfile integrity, abandoned deps, install-hook risk.
2. **Supply chain / CI** — action pinning, workflow `permissions`, dangerous triggers, Dependabot/Renovate, SBOM/provenance.
3. **Container / image** — base-image pinning & freshness, non-root, HEALTHCHECK, secrets-in-layers, `.dockerignore`, image scan.
4. **Secrets** — tree/history scan, `.gitignore` coverage, GitHub secret scanning + push protection.
5. **SAST / code** — CodeQL / code-scanning, linter-in-CI, dangerous patterns (`eval`, shell interpolation, unsanitized sinks).
6. **GitHub configuration** — branch protection, required reviews/checks, signed commits, `SECURITY.md`, `CODEOWNERS`, Dependabot alerts.
7. **Runtime hardening** — security headers, exposed ports/binds, CORS, least-privilege runtime.

Keep raw output terse — capture the signal, not the whole log.

## Phase 2 — Triage checkpoint  *(collaborative — STOP here)*
Consolidate every finding into one table, most-severe first:

| # | Domain | Finding | Severity | Exploitability (this repo) | Effort |
|---|--------|---------|----------|----------------------------|--------|

- **Severity**: Critical / High / Medium / Low / Info — intrinsic badness.
- **Exploitability (this repo)**: how reachable/relevant given the Phase 0 threat model. A high-severity
  CVE in a code path this deploy never touches is low real-world risk — say so.
- **Effort**: quick (<30 min) / medium / project.

Then **stop and hand it to the user**: ask them to mark false positives, de-scope items that don't fit the
threat model, and confirm or re-rank priorities. Do not proceed to the plan until they've weighed in.

## Phase 3 — Actionable plan  *(the deliverable)*
Turn the triaged, user-adjusted findings into a plan grouped by effort:

- **Quick wins** (<30 min each) — **Medium** — **Projects**

For each item give: the concrete change (files/config touched), the exact command or edit where possible,
**how to verify** it worked, and whether it's safe to do immediately. Sequence them (some fixes unblock or
subsume others).

Then offer the user follow-through options — pick per their preference, don't assume:
- Open GitHub issues (via GitHub MCP) for the tracked items. For anything exploitable, prefer a
  **private** GitHub security advisory over a public issue.
- Save the report so runs are comparable over time. **Never commit the report into the repo being
  audited** — a security report is a map of the project's weak spots, and on a public repo it
  advertises them to anyone. Default to a path **outside the working tree** (e.g.
  `~/<repo>-security-reports/audit-<YYYY-MM-DD>.md`) or a private store; only put it in-repo if the
  user explicitly asks *and* the repo is private. Confirm the location before writing.
- Start executing the quick wins now as a follow-up task. When you do, load
  [`references/remediation-recipes.md`](references/remediation-recipes.md) — battle-tested fixes for the
  findings this audit commonly surfaces (scan-before-push gating + finding triage, provenance/SBOM/
  signing, CodeQL, linting an upstream fork, making checks merge-blocking), each with a verify step.

Use the structure in [`references/report-template.md`](references/report-template.md) for the written report
so successive audits diff cleanly.

---

### Re-running the flow
This skill is meant to be run repeatedly. On a re-run, if a previous report exists, open it first and lead
with **what changed** (newly-introduced, fixed, still-open, regressed) before the full pass — drift over
time is the point.
