# Architecture

Twelve views of the same platform. Each one answers a question that the others
cannot, and each diagram is accompanied by the reasoning behind the parts of it
that are not obvious.

## Reading order

If you are new to the repository, read them in this order. Each builds on the last.

| # | View | Answers |
|---|---|---|
| 1 | [Architecture Overview](overview.md) | What is this, and what are the moving parts? |
| 2 | [System Context](c4-system-context.md) | Who uses it, and what does it depend on outside itself? |
| 3 | [Container Diagram](c4-container.md) | What runs, and how do the pieces talk? |
| 4 | [Deployment Diagram](deployment.md) | Where does it all physically run? |
| 5 | [GitOps Flow](gitops-flow.md) | How does a commit become running state? |
| 6 | [CI/CD Flow](cicd-flow.md) | How does code become a verified image? |
| 7 | [Bootstrap Flow](bootstrap-flow.md) | How does an empty machine become this platform? |
| 8 | [Recovery Flow](recovery-flow.md) | How is it rebuilt after total loss? |
| 9 | [Observability Flow](observability-flow.md) | How do metrics, logs, and alerts move? |
| 10 | [Networking](networking.md) | How does a packet reach a pod? |
| 11 | [DNS](dns.md) | How does a name become that packet's destination? |
| 12 | [TLS Flow](tls-flow.md) | How does a certificate come to exist, and stay valid? |

## Conventions

**Diagrams are Mermaid, not images.** They render on GitHub, they diff line by
line in review, and they cannot drift from the repository without someone editing
the file that describes them. A PNG exported from a drawing tool is correct on the
day it is exported and unfalsifiable afterwards.

**Every version number in these documents is the version actually deployed.** They
are not aspirational. Where a component appears in the original Sprint 5.1 scope
but is not deployed, the document says so rather than omitting it — see
[Observability Flow](observability-flow.md) on distributed tracing.

**Single-node facts are stated as such.** This platform runs on one node. A diagram
that implies a control-plane/worker split would be a more impressive diagram and a
false one. Where the single-node topology has a real consequence — no rescheduling,
SQLite instead of etcd, one storage class — the document names the consequence.

## What is deliberately absent

Distributed tracing. Tempo and OpenTelemetry appear in the Sprint 5.1 scope and are
not deployed. The reason is in [ADR 011](../../adr/011-distributed-tracing.md): the
backend currently has no business endpoints and the frontend calls it from the
browser, so a trace would contain a health check and two dependency calls. The
instrumentation is written and disabled; the collector is not deployed. Documenting
it as present would be the easiest lie in the repository to tell and the easiest to
catch.

## Related

- [Architecture Decision Records](../../adr/) — why each technology was chosen, and
  what was rejected
- [Operations](../operations/) — how to run it
- [Runbooks](../observability/runbooks/) — what to do when an alert fires
