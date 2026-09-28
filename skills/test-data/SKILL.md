---
name: test-data
description: Make the data a test suite assumes actually exist - list every data precondition with tf.sh preconditions, plan how to create it through the project's own seeding mechanism or its API, write an idempotent, clearly marked seed script, and run it only against a local target after the user agrees. Use for /testwright:run --seed, when cases are Blocked or failing because "an order in status shipped" or "at least 1,000 rows" does not exist, or when a user asks for test data or fixtures.
---

# Test data

> `tf.sh` = `"$CLAUDE_PLUGIN_ROOT/scripts/tf.sh"` (not on PATH).

A case whose data is missing fails for the wrong reason, and a team that
sees too many of those stops believing failures. Seeding fixes the cause
rather than the symptom.

## 1. See what is needed, free

```sh
tf.sh preconditions                       # every data need, most-used first
tf.sh preconditions --status Fail,Blocked # just the ones hurting now
tf.sh preconditions --format tsv          # need, cases, ids, source (pre|data)
```

It reads each case's **Preconditions**, split on `;`, with the login part
dropped because the engine already handles that. It also reads **Test Data**
that states a volume ("at least 1,000 orders").

## 2. Plan, with the `test-data-seeder` agent

Use the first mechanism that exists, in this order:

1. **The project's own seeds or fixtures.** Django fixtures, `rails
   db:seed`, `factory_bot`, `prisma db seed`, Knex, Laravel seeders. These
   already know the model's rules.
2. **The app's API.** The POST endpoints the `api` cases already call
   successfully.
3. **The UI.** Only as written steps for a person, never automated. It is
   slow, and a seed that depends on the UI breaks with every redesign.

**Never write SQL into the database.** It skips the app's own rules. A row
with `status = 'shipped'` that was never paid is a state the app cannot
reach, and a case run against it proves nothing.

**Reach states through the app's own transitions.** To get a shipped order,
create it, pay it, then ship it. The seed then exercises the same path a
user does.

## 3. The seed script's rules

`tests/data/seed.sh`, POSIX sh:

- **Marked.** Every record carries `tw-seed` in a name or title field, so it
  can be found and removed, and never confused with real data.
- **Idempotent.** It checks for a `tw-seed` record in the needed state before
  creating one. Running it twice creates nothing new.
- **Local only.** It refuses unless `base_url` is `localhost`, `127.0.0.1`
  or `*.local`, the same rule as the production guard.
- **No secrets.** It uses the cookie jar `tf.sh login` already made. No
  password on a command line, in the script, or in its output.
- **Volumes in a loop**, with a progress line every 100 records.

## 4. Run only on a yes

The plan (`tests/data/seed-plan.md`) is shown to the user. It creates real
records, so `sh tests/data/seed.sh` runs only when they agree. Afterwards
`tf.sh preconditions` shows what is still unmet. Those needs usually say
something the app cannot do, and that is worth a question, not a workaround.
