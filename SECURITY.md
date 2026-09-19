# Security policy

This repository is a sanitized public excerpt of a private production system.

- It contains **no credentials, tokens, keys or environment files**. The only
  secret-shaped strings are the detector regexes inside the hooks, and every test
  fixture is assembled at runtime by string concatenation so no literal token
  exists in the tree. A `gitleaks` scan ran before publication and runs in CI on every push.
- It contains **no client data, no private repository content and no machine
  paths**. Every path is repository-relative or an environment override.
- The hooks are **defensive** controls (block piping remote code into a shell,
  block credential file reads, block mass deletes, flag prompt injection). They
  add friction for mistakes; they are not a sandbox and must not be sold as one.

To report a problem with anything here, open a GitHub issue on this repository.
Do not include secrets or private data in the issue.
