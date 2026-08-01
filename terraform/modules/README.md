# Modules

Empty during Phase 1. Modules arrive with the resources that need them.

## When something becomes a module here

A module is justified when it is **called more than once**, or when it **encapsulates a
decision** that must not be re-litigated at every call site. Nothing else.

Two are planned:

| Module | Justification |
|---|---|
| `github-repository` | Called twice, for `NovaShop` and `NovaShop-GitOps` |
| `dns-record-set` | Encapsulates `proxied = false` — enabling the Cloudflare proxy breaks HTTP-01 silently, and that must be one deliberate edit rather than a per-record flag someone copies |

A single-use wrapper that only forwards its variables is indirection without abstraction. It
makes the code longer, the plan harder to read, and resource addresses deeper, in exchange
for looking modular.
