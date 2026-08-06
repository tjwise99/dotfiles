# Repo Health — domain checklists & commands

Detailed checks for Phase 1. Each check lists **what to look for**, the **command(s)** to run (prefer the
one whose tooling is present), and **why it matters**. Probe availability with `command -v <tool>` first;
if absent, mark *not-run* and fold "enable `<tool>`" into the plan. Never print raw secret values.

---

## 1. Dependencies & lockfile
- **Known CVEs in deps.**
  - npm: `npm audit --json` (and `npm audit --omit=dev --json` to separate runtime from build-time risk).
  - python: `pip-audit` / `safety check`. go: `govulncheck ./...`. rust: `cargo audit`. ruby: `bundle audit`.
    php: `composer audit`.
  - Why: transitive CVEs are the most common real exposure; runtime-vs-dev split tells you what actually ships.
- **Lockfile present & in sync.** Confirm a lockfile exists and matches the manifest (`npm ci --dry-run`,
  `npm ls` for unmet/duplicated trees). No lockfile = non-reproducible, unpinned supply chain.
- **Outdated majors.** `npm outdated` / `go list -m -u all` / `pip list --outdated`. Old majors accrete
  unpatched CVEs and make future upgrades risky.
- **Abandoned / deprecated deps.** Watch `npm ci`/install output for `deprecated` warnings; sanity-check the
  most critical deps' last-release date. Unmaintained deps won't get security fixes.
- **Install-hook / lifecycle-script risk.** Inspect `install` / `postinstall` / `preinstall` in the
  manifest and whether CI runs them (`npm ci` vs `npm ci --ignore-scripts`). Lifecycle scripts run arbitrary
  code at install — a real supply-chain surface. Note where the repo already uses `--ignore-scripts`.

## 2. Supply chain / CI hardening
- **Third-party action pinning.** `grep -rn 'uses:' .github/workflows`. Actions pinned to a **floating tag**
  (`@v4`, `@main`) can be re-pointed by the author or a compromised account; pin to a **full commit SHA** for
  third-party actions. First-party (`actions/*`, `docker/*`) tags are lower-risk but SHA-pinning is best practice.
- **Least-privilege `GITHUB_TOKEN`.** Is there a top-level or per-job `permissions:` block? Default token
  permissions are broad; declare `contents: read` and widen only where needed (e.g. `packages: write` on publish).
- **Dangerous triggers.** Flag `pull_request_target` and `workflow_run` that check out and execute **PR-author
  code** with secrets in scope — the classic CI-to-secret-exfiltration path.
- **Secret handling in workflows.** No secrets echoed to logs, no secrets passed to untrusted steps, no secrets
  in `pull_request` (fork) contexts.
- **Automated dep updates.** Presence of `.github/dependabot.yml` or Renovate config. Absent = deps rot silently.
- **Provenance / SBOM.** For published artifacts (images, packages): build provenance / attestation
  (`actions/attest-build-provenance`), SBOM generation, image signing (cosign). Absent = consumers can't verify.

## 3. Container / image
- **Base image pinning & freshness.** A floating tag (`node:22-alpine`) is not reproducible and silently
  drifts. Pin to a **digest** (`node:22-alpine@sha256:…`) and keep it fresh via Renovate/Dependabot. Confirm the
  tag is a maintained, supported line.
- **Non-root runtime.** No `USER` directive ⇒ the container runs as **root**. Add a non-root `USER`. Check for
  it: `grep -n '^USER' Dockerfile`.
- **HEALTHCHECK.** Present? Enables orchestrator restart-on-unhealthy.
- **Secrets in layers.** No `COPY` of `.env`/keys, no secrets in `ARG`/`ENV` that persist in history
  (`docker history <img>`). Multi-stage builds should not carry build secrets into the final stage.
- **`.dockerignore` coverage.** Must exclude `.git`, `node_modules`, local config/secrets — otherwise they
  leak into the build context and possibly the image.
- **Image vulnerability scan.** `trivy image <img>` / `grype <img>` / `docker scout cves <img>` if available;
  else recommend adding one (ideally as a CI gate). Scans the OS + language layers the base image drags in.
- **Minimal final image.** Multi-stage that ships only runtime artifacts (no build toolchain, no npm cache).

## 4. Secrets
- **Working-tree scan.** `gitleaks detect --no-git` / `trufflehog filesystem .` if present; else a heuristic
  grep for high-signal patterns (AWS keys `AKIA…`, private-key headers, `api[_-]?key`, bearer tokens). **Redact
  matches** to a fingerprint.
- **History scan.** `gitleaks detect` (full history) — heavier; note it's a separate, slower pass. A secret
  committed and later deleted is still in history and must be rotated, not just removed.
- **`.gitignore` coverage.** Confirm files holding secrets (real `config.js`, `.env`, key files) are gitignored
  and only a `.sample`/`.example` is tracked.
- **GitHub secret scanning + push protection.** Enabled on the repo? (GitHub MCP `run_secret_scanning`; repo
  security settings). Push protection blocks secrets *before* they land.

## 5. SAST / code
- **Code scanning / CodeQL.** Is there a CodeQL workflow or GitHub code-scanning enabled? For supported
  languages it's a high-value, low-effort add.
- **Linter in CI.** A linter configured *and enforced* in CI (not just locally). Catches a class of bugs and
  unsafe patterns pre-merge.
- **Dangerous code patterns.** Grep for high-risk sinks in the repo's languages:
  - `eval(`, `new Function(`, `child_process` with string interpolation, `exec(`/`execSync(` on user input.
  - Unsanitized DOM sinks: `innerHTML`, `dangerouslySetInnerHTML`, `document.write`.
  - SSRF-prone `fetch`/HTTP where the URL derives from external input.
  - Verify findings are real (reachable with attacker-influenced input), not just pattern hits.

## 6. GitHub configuration  *(via GitHub MCP / gh)*
- **Branch protection** on the default branch: required PR review(s), required status checks (the CI gates),
  no force-push, linear history / no direct pushes.
- **Required signed commits** (if the workflow supports it).
- **`SECURITY.md`** — a disclosure policy so reporters know where to go.
- **`CODEOWNERS`** — routes review to the right people; pairs with required-review protection.
- **Dependabot alerts + security updates** enabled.
- **Repo visibility & access** — visibility matches intent; collaborator list & permission levels are least-privilege.

## 7. Runtime hardening  *(app-specific)*
- **Security headers.** If the app serves HTTP: is a headers middleware (e.g. `helmet`) present **and actually
  wired in** (not just a dependency)? Grep for its import/use, not just its presence in `package.json`.
- **Network exposure.** What ports/addresses does it bind? Is it bound wider than needed (`0.0.0.0` when
  localhost/LAN-only suffices)? How is it published (host firewall, port-proxy)?
- **CORS / origin policy.** Not wildcard-open if it handles anything sensitive.
- **Least-privilege runtime.** Read-only mounts where possible (this deploy mounts `config.js:ro`), dropped
  capabilities, no `--privileged`, resource limits.

---

### Quick availability probe
```bash
for t in npm npx gitleaks trufflehog trivy grype docker-scout syft cosign \
         pip-audit safety govulncheck cargo-audit; do
  command -v "$t" >/dev/null 2>&1 && echo "present: $t" || echo "absent:  $t"
done
```
Run once at the start of Phase 1 so you know which checks are live vs guide-only.
