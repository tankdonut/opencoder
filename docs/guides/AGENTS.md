# docs/guides/ — User-Facing Documentation

## Audience Split (CONVENTION)

| File | Audience | Style |
|------|----------|-------|
| `installation.md` | Agents | Terse, command-first, optimized for automated consumption |
| `installation-detailed.md` | Humans | All-platforms prose, explanations, troubleshooting |

Do NOT duplicate content between them. `installation.md` stays terse; `installation-detailed.md` carries the narrative.

## Version Source of Truth

**NEVER hardcode plugin or OpenCode versions in prose.** Reference the SoT instead:

- Plugins → `build/.opencode/opencode.json`
- OpenCode release → `build/.opencode-version`
- Checksums → `build/.opencode-checksums`

When versions change, point readers to those files rather than restating (and drifting from) the values.

## Files

| File | Purpose |
|------|---------|
| `configuration.md` | Config reference + module toggle env vars |
| `installation.md` | Agent-optimized install guide |
| `installation-detailed.md` | Human-optimized, all-platforms guide |
| `usage.md` | Workflows + CI/CD examples |

## Conventions

- Link to root `AGENTS.md` for agent instructions; don't restate.
- Commands use Podman first, Docker second (matches project convention).
- Cross-reference `build/AGENTS.md` for build-context internals, `scripts/AGENTS.md` for script details.
- Two-Tier Config rule (plugins vs runtime) is documented in root `AGENTS.md` and `build/AGENTS.md` — do not re-explain here.
