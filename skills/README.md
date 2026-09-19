# skills

A **skill** is a single Markdown file (`SKILL.md`) that teaches an agent runtime a
procedure it should follow when a specific situation is detected. Each file has:

- **Frontmatter** — `name` (matches the directory) and `description`. The description
  states when the skill fires, what it does NOT cover (so it doesn't overlap a
  neighboring skill), and enough trigger language for a runtime to match it against a
  task.
- **Body** — when it fires, what goes wrong without it, a numbered procedure, hard
  rules, common failure modes, a self-check checklist, and honest limits (what the
  skill does not guarantee).

## How a runtime loads them

A typical loader scans a `skills/` directory, reads each `SKILL.md` frontmatter to build
an index of name → description, and — when a task matches a description — loads the full
body into context before acting. Skills are procedural memory: they encode "how we do X
here," verified once and reused, instead of re-deriving the same steps from a general
instruction every session.

## Included

| skill | fires on |
|---|---|
| `task-tracking` | any multi-step session, so no step is silently dropped |
| `untrusted-data-boundary` | moving another system's output into a prompt or shared log |
| `eval-design` | designing a benchmark, change gate, or success metric |
| `secret-leak-response` | a credential was committed, pushed, or logged |
| `tamper-evident-publish` | automation committing and pushing to a shared repo |
