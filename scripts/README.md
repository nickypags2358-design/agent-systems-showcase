# scripts

## agents-md-drift.sh

Compares two instruction files (a "canon" and a hand-adapted "mirror" — for example, two
different agent-runtime config files derived from the same source) and reports which
top-level Markdown section headings exist in one but not the other. Exits 0 when in sync,
1 when drifted, 2 on a usage/file error.

```bash
scripts/agents-md-drift.sh <canon.md> <mirror.md>
```

## Demo

`scripts/fixtures/a.md` and `scripts/fixtures/b.md` are a tiny canon/mirror pair with
one section that differs (`Escalation` vs `Legacy Notes`) to demonstrate drift output:

```bash
scripts/agents-md-drift.sh scripts/fixtures/a.md scripts/fixtures/b.md
```
