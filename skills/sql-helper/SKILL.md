---
name: sql-helper
description: >
  Lab Postgres helper. Use whenever the user asks to run SQL, inspect a
  schema, or load lab data into the local Postgres.

  Subcommands:
    init       — start Postgres, create the `dmdb` database, load lab data
    schema     — dump schema of the `dmdb` database
    query "Q"  — run SQL Q against `dmdb`, return rows
    explain "Q"— run EXPLAIN ANALYZE Q

  Usage: bash skills/sql-helper/helper.sh <subcommand> [args]
---
