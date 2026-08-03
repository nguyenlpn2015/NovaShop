# Security Policy

NovaShop treats security as a core engineering and operational responsibility.

## Supported Versions

Security updates are provided for the latest released version and the current
default branch. Pre-release versions and older releases may receive fixes at
the maintainers' discretion.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Default branch | Yes |
| Older releases | No |

## Reporting a Vulnerability

Do not report suspected vulnerabilities through public issues, discussions,
pull requests, or social media.

Use GitHub's **Report a vulnerability** feature in the repository's Security
tab. If private vulnerability reporting is unavailable, email
nguyen.lephuoc@smartdev.com with the subject `NovaShop Security Report`.

Include, where possible:

- the affected component and version;
- a clear description of the issue and its impact;
- reproducible steps or a minimal proof of concept;
- relevant logs or screenshots with secrets and personal data removed;
- suggested remediation, if known;
- whether the issue has been disclosed elsewhere.

Do not include live credentials, personal data, or destructive payloads.

## Response Process

Maintainers aim to:

- acknowledge a report within three business days;
- provide an initial assessment within seven business days;
- keep the reporter informed of material progress;
- coordinate remediation and disclosure based on severity and affected users;
- credit the reporter when requested and appropriate.

These are service objectives, not guarantees. Complex or externally dependent
issues may require additional time.

## Disclosure

Please allow maintainers reasonable time to investigate and remediate before
public disclosure. Once a fix is available, maintainers may publish a GitHub
Security Advisory, release notes, upgrade guidance, and appropriate credits.

## Safe Harbor

Good-faith research that follows this policy, avoids privacy violations and
service disruption, and reports findings promptly will be treated as
authorized for the purpose of improving NovaShop's security.

## Vulnerability Scanning and What Blocks a Release

Container images are scanned by Trivy in
[`.github/workflows/release.yml`](.github/workflows/release.yml) before the
workflow holds any registry credential. The image is built into the local daemon
with `push: false`, scanned, and only then is a login performed — so an image
that fails the scan has nowhere to go. This ordering is the control; it is not a
convention that a later edit can quietly break without also moving the login
step.

The gate is deliberately narrower than "no vulnerabilities", and the boundary is
worth stating precisely:

| Setting | Value | Why |
| --- | --- | --- |
| `scanners` | `vuln,secret` | Package vulnerabilities and committed secrets |
| `severity` | `CRITICAL,HIGH` | MEDIUM and below are reported by Dependabot, not release-blocking |
| `exit-code` | `1` | A finding fails the job, and therefore the release |
| `ignore-unfixed` | `true` | **See below** |

### Why `ignore-unfixed` is enabled

`ignore-unfixed: true` means a CRITICAL or HIGH vulnerability with **no
available fix** does not block a release.

This is an accepted risk, not an oversight. A base image frequently carries
disclosed vulnerabilities for which no patched package has yet been published by
the distribution. Failing the build on those produces a pipeline that cannot
release at all, for a condition no change to this repository can clear — and a
gate that blocks everything is one that gets bypassed, which is strictly worse
than a gate with a stated boundary.

The consequence is explicit: **an unfixed CRITICAL vulnerability can be present
in a published image.** What limits the exposure is that base images are pinned
and updated by Dependabot, so a fix is picked up as soon as one exists, and the
scan output is retained on every release run rather than discarded.

To see what is currently being tolerated, drop the flag locally — no credential
is required, and nothing is published:

```sh
docker build -t novashop-backend:audit backend
trivy image --scanners vuln --severity CRITICAL,HIGH novashop-backend:audit
```

If that output ever contains a **fixed** CRITICAL or HIGH, the release gate is
not working and it should be reported through the process above.

## Operational Security

- Never commit secrets or sensitive production data.
- Use least privilege and short-lived credentials where supported.
- Report accidentally exposed credentials immediately; deletion from Git
  history does not remove the need for credential rotation.
- Security fixes must receive appropriate review and validation before release.
