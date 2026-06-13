# build-loop

The **BUILD agent (Agent B)** in a two-agent `design → build` pipeline where work is tracked as **GitHub Issues**.

Agent B takes faithful execution of work that's already been designed: it reads issues labeled `ready`, builds each on its own branch off `main`, opens a PR that closes the issue, and moves the label through `building` → `in-review`. It never designs, never decides *what* to build, and never edits the spec — the issue **is** the spec.

## The iron rule

Every build runs in **its own git worktree**, cut from the freshest `main`. The repo's main checkout stays parked on `main` (it belongs to the designer), so design and build never collide and any number of builds can run in parallel.

## How it works

- The hopper is **GitHub Issues** — synced across machines, backed up automatically.
- Builds **one** feature by default; drains the whole hopper only when asked to keep going.
- A single named feature builds in the **foreground**; "build them all" / multiple issues / "in the background" fans out one background sub-agent per issue, each in its own worktree.

## Triggers

"build the next feature", "drain the hopper", "build the ready issues", "keep building", "fix this bug", or any development/build work on a GitHub-Issues pipeline.

## Companions

- **design-queue** (Agent A) — designs and specs the work B builds.
- **quality-gate** — proves a build is correct/secure before it advances to `in-review`.

## Install

Clone, then link the skill folder into `~/.claude/skills/` (Windows junction shown):

```powershell
git clone https://github.com/iwantedjusttom/build-loop.git
New-Item -ItemType Junction -Path "$HOME\.claude\skills\build-loop" -Target "<path>\build-loop"
```
