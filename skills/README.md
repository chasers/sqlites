# Claude Code skills

Canonical home for this repo's [Claude Code skills](https://code.claude.com/docs/en/skills).
Each `<name>/SKILL.md` here is the single source of truth and is committed.

`.claude/` is **git-ignored** (a per-user directory), so the symlink that makes
a skill load is a one-time local setup step — the same way you'd enable any
skill for yourself:

```sh
./skills/install.sh            # link into ./.claude/skills  (loads in this repo)
./skills/install.sh --global   # link into ~/.claude/skills  (loads from any directory)
```

The script is re-runnable (correct links are left alone, stale ones replaced)
and adds every `skills/<name>/` it finds. Claude Code follows the symlinks and
de-duplicates if the same target is reachable from more than one location, so
running both is fine.

Prefer to do it by hand? It's just:

```sh
ln -s "$PWD/skills/query-alpha-db" .claude/skills/query-alpha-db      # in-repo
ln -s "$PWD/skills/query-alpha-db" ~/.claude/skills/query-alpha-db    # global
```

## Skills

- **`query-alpha-db`** — run SQL against a live database on the smolsqls alpha
  deployment (`https://alpha.smolsqls.com`) over the HTTP query API. Credentials
  come from environment variables; nothing secret is committed.

## Adding a skill

1. Create `skills/<name>/SKILL.md` (frontmatter `name` + `description`; the
   **directory name** is what identifies the skill).
2. Commit the skill directory.
3. Run `./skills/install.sh` to link it in (don't commit anything under
   `.claude/` — it's ignored).
