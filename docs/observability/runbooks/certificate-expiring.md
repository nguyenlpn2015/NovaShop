# Runbook: CertificateExpiring

**Severity:** critical · **Fires after:** 1 hour · **Threshold:** fewer than 21 days remaining

## What it means

A cert-manager certificate is inside 21 days of expiry. Let's Encrypt issues for
90 days and cert-manager renews at roughly two thirds of the lifetime, so a
healthy certificate should never drop below about 30 days.

Reaching 21 means **renewal has already been failing for over a week**. The
threshold is set here deliberately: it is late enough to be unambiguous and early
enough to leave three weeks to fix it.

## Impact

None yet — that is the point of alerting three weeks out. If it does expire, every
browser refuses the site and the failure is total and public.

## Diagnose

```sh
sudo k3s kubectl get certificates -A
sudo k3s kubectl describe certificate <name> -n <ns> | sed -n '/Status/,$p'
sudo k3s kubectl get certificaterequests -A
sudo k3s kubectl get challenges -A
sudo k3s kubectl -n cert-manager logs deploy/cert-manager --tail=100
```

A pending Challenge is the usual finding. Validation is HTTP-01, so the chain
that must work is: public DNS resolves to this host, port 80 reaches Traefik, and
Traefik routes `/.well-known/acme-challenge/` to the solver pod.

```sh
curl -sv http://<domain>/.well-known/acme-challenge/test 2>&1 | tail -20
```

## The rate limit matters here

Let's Encrypt production allows **5 duplicate certificates per 168 hours**. Deleting
a Certificate to "force a retry" issues a new order each time and can burn the
week's budget in an afternoon, leaving the certificate genuinely unrenewable until
the window rolls.

Fix the underlying validation failure first. Check remaining budget by reading the
CertificateRequest history before creating any new order:

```sh
sudo k3s kubectl get certificaterequests -A --sort-by=.metadata.creationTimestamp
```

If the budget is already spent, switch the issuer to Let's Encrypt **staging** to
debug validation, and only move back to production once a staging certificate
issues cleanly.

## Fix

| Finding | Action |
|---|---|
| Challenge pending, HTTP 404 | Traefik is not routing the solver — check the Ingress and Traefik logs |
| Challenge pending, DNS wrong | Correct the record; nothing in the cluster can fix this |
| Order failed, rate limited | Wait for the window, or debug on staging |
| cert-manager not watching | Check inotify limits — an exhausted watcher makes cert-manager stop noticing work |

## Verify

```promql
(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400
```

Should read close to 90 after a successful renewal.
