# Remediation recipes

Battle-tested fixes for the findings this audit most commonly surfaces. Load this **after** the plan
is agreed (Phase 3), when executing — not during the read-only audit. Each recipe: what/why, the
concrete change, and how to verify. Adapt to the repo's ecosystem and threat model; these examples are
Node + GitHub Actions + GHCR but the shapes generalize.

**Two conventions that apply to every CI recipe below:**
- **SHA-pin every new action** with a trailing `# vN` comment. Resolve tag → commit SHA with
  `git ls-remote https://github.com/<owner>/<action> <tag> <tag>^{}` — take the `^{}` (dereferenced)
  line for annotated tags, else the plain line. If the repo has Dependabot's `github-actions`
  ecosystem enabled, the pins stay fresh automatically.
- **Least privilege**: default the workflow to `permissions: contents: read` and let each job opt into
  exactly what it needs.

---

## Supply chain / CI

### Image vuln scanning as a blocking gate (scan-BEFORE-push)
Don't scan the image after pushing — a vulnerable image is already published. Build into the local
daemon, scan, then push only on a clean result.

```yaml
- uses: docker/build-push-action@<sha> # vN
  with: { context: ., load: true, push: false, tags: app:scan }
- name: Scan image with Trivy
  uses: aquasecurity/trivy-action@<sha> # vN
  with:
    image-ref: app:scan
    severity: HIGH,CRITICAL
    ignore-unfixed: true      # don't block on CVEs with no available fix
    exit-code: '1'            # fail the job → blocks the push step
    format: sarif
    output: trivy-results.sarif
- name: Upload SARIF
  if: always()               # upload even when the gate fails — that's when you want it
  uses: github/codeql-action/upload-sarif@<sha> # vN
  with: { sarif_file: trivy-results.sarif, category: trivy }
# ...only now build+push...
```
Needs `security-events: write` for the SARIF upload. `load: true` is single-arch only — fine for a
single-arch publish. Verify locally with the `ghcr.io/aquasecurity/trivy` container (mount the docker
socket) using the exact same flags before wiring CI.

### Triaging scan findings — two recurring shapes
A blocking gate is only landable if it's green. Expect to triage before it passes:
- **Package-identity false positive** — the scanner matches the repo's own `package.json`
  name+version against an upstream advisory for a same-named project, even when the vulnerable code
  was stripped out. **Confirm the sink is absent** (e.g. grep for the vulnerable route/API), then
  suppress in `.trivyignore` with a code-referenced justification (never a bare CVE id):
  ```
  # CVE-XXXX — "<title>": package-name false positive. This fork has no <sink>
  # (routes in js/server.js are only /a, /b). Not exploitable. Re-verify if <sink> is added.
  CVE-XXXX
  ```
- **Base-image-bundled component** — the vuln is in something the base image ships (e.g. the
  bundled `npm`'s vendored `undici`), not your dependency, and the latest base tag still carries it
  (a Dependabot base bump won't help). If that component isn't used at runtime, **remove it in the
  runtime stage** — a real fix that also slims the image:
  ```dockerfile
  RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
  ```
  First confirm nothing invokes it at runtime (grep for `child_process`/spawn/the tool name), then
  rebuild + rescan (expect exit 0) and boot the image to confirm it still serves.

### Build provenance + SBOM + signing on publish
Attach supply-chain metadata to the published image. On the push `build-push-action` add
`provenance: mode=max` and `sbom: true`, then:
```yaml
- uses: actions/attest-build-provenance@<sha> # vN
  with:
    subject-name: ghcr.io/${{ github.repository_owner }}/<image>
    subject-digest: ${{ steps.build-and-push.outputs.digest }}
    push-to-registry: true
- uses: sigstore/cosign-installer@<sha> # vN
- run: cosign sign --yes "ghcr.io/${{ github.repository_owner }}/<image>@${{ steps.build-and-push.outputs.digest }}"
```
Needs `id-token: write` (OIDC — shared by cosign *and* the attestation; keyless, no secret),
`attestations: write`, and `packages: write`. Signing/attesting is **by digest**, so a single
`:latest` tag is fine — no metadata-action needed. These steps only run on the real publish trigger
(often skipped on PRs), so verify on the first post-merge run:
`cosign verify …@<digest>`, `gh attestation verify`, and `docker buildx imagetools inspect <image>`
(look for an `attestation-manifest`).

---

## SAST / code

### CodeQL (config-as-code, not "default setup")
A dedicated workflow keeps the actions SHA-pinned + Dependabot-tracked and isolates its
`security-events: write` scope:
```yaml
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }
  schedule: [{ cron: '17 7 * * 1' }]   # weekly — new queries catch issues without a code change
jobs:
  analyze:
    permissions: { contents: read, security-events: write }
    steps:
      - uses: actions/checkout@<sha> # vN
      - uses: github/codeql-action/init@<sha> # vN
        with: { languages: javascript-typescript, config: "paths-ignore:\n  - vendor\n  - fonts" }
      - uses: github/codeql-action/analyze@<sha> # vN
        with: { category: "/language:javascript-typescript" }
```
The job's check name is `Analyze (<Language>)`; the action also posts a `CodeQL` check.

### Linting an upstream fork (strict on ours, lenient on vendored)
Greenfield linting of a fork drowns in noise from framework code you don't maintain. Split scope:
- **Strict** (`@eslint/js` recommended) on the code you own — custom modules, tests, tooling.
- **Lenient** on the vendored/upstream core — declare its runtime globals and turn off only the
  legacy-style rules (`no-undef`, `no-redeclare`, `no-unused-vars`, `no-global-assign`,
  `no-prototype-builtins`, `no-useless-assignment`); keep the structural recommended rules on so real
  bugs (dupe keys, unreachable, cond-assign) still trip.
- Let each frontend file's own `/* global Foo, Bar */` header own its framework globals — declaring
  the same names in the flat config too triggers `no-redeclare`. Make each header match actual usage.
- ESLint 9+ doesn't read `.gitignore` — explicitly `ignores` any gitignored, secret-bearing file
  (e.g. a real `config/config.js`) so it's never linted.
- Wire it as a blocking `lint` job and add it to the publish job's `needs`.

---

## GitHub configuration

### Add checks to the required-status-checks set (make them merge-blocking)
A new CI job runs and shows on PRs but **does not block merge** until it's in the ruleset's required
list. Update the ruleset (repo → Settings → Rules, or the API). **The update verb is `PUT`, not
`PATCH`** (`PATCH` 404s), and you must send the full `rules` array — fetch, append to the
`required_status_checks` rule's `required_status_checks: [{context: "<job name>"}]`, then PUT it back.
Match the *check name* exactly (usually the job name, e.g. `lint`, `Analyze (JavaScript/TypeScript)`).
Verify by re-reading the ruleset and confirming the other rules (reviews, deletion, non-fast-forward)
are untouched.

---

## General verification discipline
- **Blocking gates must be proven green before landing**, or the first push breaks the pipeline. Run
  the scanner/linter locally with the CI-exact flags; triage findings; re-run to exit 0.
- **Steps gated to the publish trigger** (scan/provenance/sign inside a push-only job) can't be
  exercised by a PR — call that out and verify on the first post-merge run.
- Behavior-preserving refactors (lint fixes, dead-code removal) still need the **test suite** run —
  removing an "unused" method can break a test that asserts it exists.
