# Security Policy

## Reporting a vulnerability

If you believe you've found a security vulnerability in c11, please **do not open a public issue**. Report it privately through one of these channels:

- **GitHub Security Advisories** (preferred): <https://github.com/Stage-11-Agentics/c11/security/advisories/new>
- **Email**: `benevolent.futures@gmail.com` — please put `c11 security` in the subject line.

We aim to acknowledge receipt within 3 business days, work with you to understand and reproduce the issue, and coordinate public disclosure once a fix has shipped.

## Supported versions

c11 is pre-1.0 and ships as a rolling release via the `stage-11-agentics/c11` Homebrew tap and DMG downloads on the [Releases](https://github.com/Stage-11-Agentics/c11/releases) page. Security fixes land on the latest version — users are expected to update promptly. Older versions are not maintained.

## Scope

c11 is a macOS desktop app with a local Unix socket API, an embedded terminal (Ghostty), an embedded browser (WKWebView), and an agent-facing metadata layer. In-scope reports include:

- Arbitrary code execution via crafted socket commands, malformed metadata, or malicious terminal output.
- Privilege escalation, sandbox escape, or TCC / entitlement abuse specific to c11.
- Credential or secret leakage in logs, crash reports, or persisted workspace state.
- Auto-update / Sparkle signature or delivery issues specific to c11's release pipeline.

Out of scope:

- Social engineering against operators.
- Vulnerabilities in upstream dependencies (Ghostty, Sparkle, Bonsplit, etc.) that are not exploitable through c11's configuration — please report those to the respective upstream projects.
- Issues that require physical access to an already-compromised machine.

## Safe harbor

We will not pursue legal action against researchers who:

- Act in good faith and make a reasonable effort to contact us before any public disclosure.
- Avoid privacy violations, data destruction, and service disruption.
- Do not exploit a finding beyond what's necessary to demonstrate the issue.

Thank you for helping keep c11 and its users safe.
