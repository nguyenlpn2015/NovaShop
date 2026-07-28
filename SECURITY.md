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

## Operational Security

- Never commit secrets or sensitive production data.
- Use least privilege and short-lived credentials where supported.
- Report accidentally exposed credentials immediately; deletion from Git
  history does not remove the need for credential rotation.
- Security fixes must receive appropriate review and validation before release.
