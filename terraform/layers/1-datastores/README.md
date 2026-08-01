# Layer 1 — Datastores

PostgreSQL roles, databases, and grants; Redis configuration.

> **Phase 1: foundation only.** No resources are declared. `terraform plan` produces an
> empty plan and evaluates the outputs from variables alone.

## Why this is the most valuable layer

`cyrilgdn/postgresql` models roles, databases, and grants as real resources with real state.
That turns the platform's least-privilege story from something that happened once into
something that is continuously true.

The concrete case: **PostgreSQL 14 grants `CREATE` on the `public` schema to `PUBLIC`** —
PostgreSQL 15 removed it. So granting the metrics exporter `pg_monitor` left it able to
create tables in the application's database. The fix was to revoke that grant from `PUBLIC`
and give it to the application role only.

Today that fix is a SQL snippet someone ran and a sentence in a document. Nothing detects it
being undone. After this layer, an accidental re-grant appears in `terraform plan`.

Two `check` blocks assert the property directly, so a change that widens the exporter's
privileges fails review rather than passing quietly.

## Redis has no provider, and is handled honestly

There is no Redis Terraform provider worth depending on for server configuration. Redis is
handled the same way as the node layer: configuration rendered from a template, hash as the
trigger, existing idempotent script as the executor.

One `check` block refuses a bind list containing only loopback. Redis reachable only on
`127.0.0.1` is unreachable from pods, and the symptom is every backend replica failing its
readiness probe — a platform outage presenting as an application fault.

## `sslmode` defaults to `require`

Not `disable`. PostgreSQL is reached over the LAN and the pod network, and defaulting to
clear text for convenience is the kind of decision that is never revisited. If TLS is not
configured on the instance yet, that should be a visible failure and a deliberate override,
not a silent default.

## Verifying least privilege for real

The plan is not proof. Check the instance:

```sh
sudo -u postgres psql -d novashop \
  -c "SELECT has_schema_privilege('novashop_exporter', 'public', 'CREATE');"
```

Expect `f`. It returned `t` before the grant was revoked from `PUBLIC`.

And confirm the application is unaffected — a permission change that quietly breaks the
application is worse than the permission it fixed:

```sh
sudo -u postgres psql -d novashop \
  -c "SELECT has_schema_privilege('novashop', 'public', 'CREATE');"
```

## Configuration

```sh
export TF_VAR_postgres_superuser_password=...
cp ../../examples/1-datastores.tfvars.example terraform.tfvars

cp ../../examples/backend-local-override.tf.example backend_override.tf
terraform init
terraform plan
```

## A note on destroying this layer

The `pg` backend authenticates as a role in this same instance. Later phases put
`prevent_destroy` on the managed roles, and the backend uses a dedicated role that this layer
does not manage, so a `destroy` here cannot remove the credential the state depends on.
