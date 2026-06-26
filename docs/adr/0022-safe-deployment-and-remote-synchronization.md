# ADR 0022: Safe Remote Synchronization and Environment-Isolated Pushes

## Context
Deploying and synchronizing the codebase to a remote host (GitHub) can fail due to credential overriding (e.g. invalid `GITHUB_TOKEN` set in CI or terminal environments) or concurrent push conflicts.

## Decision
1. **Unset Overriding Tokens**: Run remote Git push commands in a sanitized environment, specifically unsetting `GITHUB_TOKEN` when the local keychain/keyring contains the valid developer credential.
2. **Pre-flight Dry Run**: Execute `git push --dry-run` prior to any actual push to ensure remote state verification and prevent unexpected conflicts.
3. **Avoid Unsafe Force-Pushes**: Prohibit standard `--force` pushes in favor of `--force-with-lease` combined with `--force-if-includes` when history rewrites are necessary.

## Consequences
- Pushes are executed safely without being blocked by temporary or invalid environment tokens.
- Conflicts are caught in dry-run mode before modifying the remote git state.
