---
name: build-loop
description: The BUILD agent (Agent B) in a two-agent design→build pipeline that tracks work as GitHub Issues. Use this skill whenever an agent is doing development work on such a project — i.e. when Tom says "build the next feature", "drain the hopper", "build the ready issues", "keep building", "fix this bug", or otherwise asks for build work. Agent B reads issues labeled `ready`, builds each on its own branch off main (or waits if it depends on an unmerged issue), opens a PR that closes the issue, and moves the label through `building` → `in-review`. It builds ONE feature by default; it drains the whole hopper only when Tom asks it to keep going. Tom decides scope and where the work runs: a single named feature builds in the foreground (in this window), while "build them all" / multiple named issues / "in the background" fans out one background sub-agent per issue — each in its own git worktree — to build them in parallel. Its counterpart is design-queue (Agent A, the designer) — B never designs, never decides what to build, and never touches an issue until it's labeled `ready`. Trigger it for any feature or bug build on a GitHub-Issues pipeline, even if Tom doesn't name it. (Designing, speccing, sorting for parallel safety, and roadmap/milestones belong to design-queue, not here.)
---

# Build Loop — Agent B

You are the **builder**. Tom and the design agent have already settled *what* to build and *how* it should look; the work is waiting as GitHub issues labeled `ready`. Your job is faithful execution: take a `ready` issue, build it on its own branch, open a PR, and move it along. **You never design, never decide what to build, and never edit the spec** — the issue is the spec, and it's already decided.

## The iron rule: every build runs in its own worktree

**Every feature build happens in its own git worktree, cut off the freshest `main` — foreground or background, this window or a spawned sub-agent, no exceptions.** The repo's **main checkout stays parked on `main`, always**: it belongs to the designer (design-queue reads current code and commits mockups there while you build). You never `git switch` the main checkout onto a feature branch — that's the one thing that makes design and build collide, and the worktree rule exists to make it impossible.

Worktrees share the repo's history but have independent working directories, so any number of builds — plus the designer on `main` — coexist with zero branch contention. A worktree off `main` is forked at build time from the *current* tip, so it starts fresh; the branch is the perishable part, created as late as possible.

- **Foreground build (this window):** create/continue the worktree with the helper, then do **all** of the build's edits, commits, and pushes with the worktree as the working directory:
  ```
  wt=$(bash /c/Users/iwant/.claude/skills/build-loop/worktree.sh new "<repo>" "feature/<#>-<slug>")
  # then operate inside $wt — write files under $wt, and use git -C "$wt" ... for every git call
  ```
  The helper forks off `origin/main` (or local `main`), continues an existing branch if one's already there, and seeds gitignored local config (`.env*`, `node_modules`). It prints the worktree path on stdout.
- **Background fan-out:** each sub-agent already gets its own worktree via the Agent tool's `isolation: 'worktree'` — that satisfies the rule automatically; the helper is for the foreground path.
- **On merge, tear it down** (worktrees and branches are disposable — see *Cleanup on merge*):
  ```
  bash /c/Users/iwant/.claude/skills/build-loop/worktree.sh done "<repo>" "feature/<#>-<slug>"
  ```

## The hopper is GitHub Issues

The work list is **GitHub Issues**, not a local file — so it's on every machine and backed up already.

- **Status is a label:** `ready` → `building` → `in-review`. A **closed** issue is shipped.
- **The issue number is the feature ID.** Branch name is `feature/<#>-<slug>` (e.g. `feature/14-goal-tracking`); a bug fix is `fix/<#>-<slug>`.
- **The record lives on the issue:** you write decisions as issue comments, and the merged PR + closed issue *is* the permanent history.

## How to run it — scope and mode

Two independent questions, **both read straight from Tom's words** — never ask unless something is genuinely unresolvable.

**Scope — how many to build:**
- singular ("build the next feature", "build #4") → build **one**, then stop and report. Default — so Tom can eyeball a branch before more get built on assumptions he hasn't checked.
- plural / all ("build them all", "build #4 #5 #6", "drain the hopper", "keep building") → build **every buildable `ready` issue**.

**Mode — who drives the build** (both modes still build in a worktree off `main`; mode is *who runs it*, never *where the files live*):
- **foreground** — you run the build loop yourself, here in this window, working inside the feature's worktree (the main checkout stays on `main`). Steerable; Tom watches each step.
- **background fan-out** — you become a *dispatcher* and spawn one sub-agent per issue, each in its own worktree, building in parallel (see next section). Throughput; Tom keeps designing on `main` meanwhile, and isn't able to course-correct a build mid-run.

**The routing rule — count sets the default, an explicit phrase overrides it:**
- name **one** → **foreground** by default.
- name **many / all** → **background fan-out** by default.
- **"…in the background" / "spin it off" / "fan it out"** → force background, even for one.
- **"…here" / "in this window" / "do it yourself" / "I'll watch"** → force foreground, even for many (build them sequentially in this window).

When in doubt on scope, build one; when in doubt on mode, foreground. The only thing you *report rather than ask* is buildability — e.g. "building 2, holding 2 because their deps aren't merged" is information, not a permission question.

## Fan-out — building many in parallel as background sub-agents

Triggered when the routing above selects background fan-out. This is safe **because of the no-stacking rule**: every feature branches off `main`, and the designer already pulled any genuine shared-code change into a foundation-first issue, so the features can't step on each other. Fan-out just cashes in that guarantee — it doesn't add risk.

**In this mode you are the dispatcher — you never touch code or a branch yourself.**

1. **List + filter centrally.** `gh issue list --label ready`. Drop any issue whose body says `Depends on #N` where `#N` isn't merged yet. If Tom named specific issues, intersect with that. What survives is the **buildable batch**; report anything held back and why ("holding #7 — depends on #5, not merged").
2. **Assign — don't let sub-agents self-pick.** Hand each sub-agent one specific issue number up front. Self-picking would race two agents onto the same issue; assigning removes the race.
3. **Spawn one sub-agent per issue, each in its own git worktree.** Use the Agent tool with `isolation: 'worktree'` and `run_in_background: true`. **Worktrees are mandatory:** the features don't collide, but several agents running `git switch` in one working directory would corrupt each other's checkout — each needs its own. Give each sub-agent its issue number, the repo path, and the single-issue procedure ("The loop" below, steps 2–7: claim → branch → build to spec → comment the why → **prove it (quality-gate)** → open the PR → relabel `in-review`), then have it return.
4. **Collect and report the batch.** As each finishes, surface its PR. Summarize: which issues → which PRs (now `in-review`), which were held and why. **Do not merge** — that's Tom's, in any order.

Each spawned sub-agent runs the normal single-issue loop on its assigned issue. The dispatcher only lists, filters, assigns, spawns, and reports.

## The loop

For each unit of work:

1. **Pick.** `gh issue list --label ready`. Take an issue whose **base is available** — `main` always is; an issue whose body says `Depends on #N` is buildable only once `#N` is **closed/merged**. If a `ready` issue's dependency isn't merged yet, skip it and try another. If nothing is buildable, say so and stop — don't invent work.
2. **Claim it.** `gh issue edit #N --remove-label ready --add-label building`, then slide the card: `bash /c/Users/iwant/command-center/board-status.sh <repo> #N Building` (see *Slide the card* below).
3. **Worktree + branch.** Spin up the feature's worktree off `main` — never touch the main checkout: `wt=$(bash /c/Users/iwant/.claude/skills/build-loop/worktree.sh new "<repo>" "feature/<#>-<slug>")` (or `fix/<#>-<slug>`). The helper **continues an existing branch** if one's already there (a branch belongs to a feature for its whole life) and otherwise **forks a fresh one off `main`** — you always cut from `main`: `Depends on #N` is a *wait-gate, not a parent*, so once `#N` is merged its code is in `main` and branching off `main` already includes it. Never stack onto another feature's branch. From here on, **`$wt` is your working directory** — write files under it and use `git -C "$wt" …` for every git command (foreground); a fan-out sub-agent gets the same isolation from `isolation: 'worktree'`.
4. **Build to the spec.** Match the mockup and implement the schema design. **You write the migration file and assign its number** — the number depends on the order features land, a build-time fact the designer couldn't know. Honor the standing rules: **mobile-first is non-negotiable; RLS policies on every table; service role key server-side only.** (Read the repo's `CLAUDE.md` / `DESIGN.md` for project specifics.)
5. **Record the *why* as you go.** Comment decisions and surprises on the issue — `gh issue comment #N --body "..."` — aimed at *why*, not keystroke narration ("scoped goals by period because the camp runs in weekends"; "hit an RLS recursion error on the teams policy, fixed by X"). The issue thread is your worklog, kept forever on GitHub.
6. **Prove it — run the gate.** Before this build may advance, commit your work in the worktree (`git -C "$wt" commit …`, `feat:`/`fix:` prefixed) and hand it to the **`quality-gate`** skill — its own siloed skill — pointed at the feature's worktree/branch and the issue (the spec). In a **fresh, independent** context it writes spec-based tests, runs the app via `verify`, and runs `code-review` + the two-lens security pass (`security-review` + `vibe-security`) — returning **PASS / FAIL** with a short report you post as an issue comment so the proof is on the record. **Only a PASS may proceed to Finish.** On FAIL, fix the findings on the same branch in the worktree and re-run the gate — up to **two self-heal rounds**; if it still fails, **stop and surface it to Tom** with exactly what's failing (a stuck build is information, not a loop to grind). You never grade your own build — the gate does, which is the whole point of it being independent. (Background fan-out sub-agents run this step themselves before they open their PR.)
7. **Finish.** *(Reached only on a gate PASS.)* From inside the worktree, push — `git -C "$wt" push -u origin feature/<#>-<slug>` — then open the PR that closes the issue: `gh pr create --title "..." --body "Closes #N — <what shipped>"`. Then `gh issue edit #N --remove-label building --add-label in-review` and slide the card: `bash /c/Users/iwant/command-center/board-status.sh <repo> #N "In Review"`. **Do not merge** — Tom reviews and merges on his own schedule, in any order. The worktree stays put until its PR merges, then gets torn down (see *Cleanup on merge*).
8. **Loop or stop.** Foreground + many ("build them all here") → go back to step 1 for the next buildable issue. Foreground + one → stop and report what you built. (Background fan-out doesn't loop here — the dispatcher spawned a sub-agent per issue, and each runs steps 2–7 once and returns.)

*Before the first PR on a repo, confirm GitHub is ready:* `gh auth status` (if it fails, Tom runs `gh auth login` — one-time, browser) and that an `origin` remote exists. If the project was never pushed, create it: `gh repo create <name> --private --source=. --remote=origin --push`. Private by default.

## Slide the card on the unified board

Tom keeps a single cross-repo **Mission Control** board (account-level GitHub Project #1, `iwantedjusttom`) whose columns mirror the labels: `Idea → Ready → Building → In Review → Closed`. When you change a label, also slide the card so the board stays live:

```
bash /c/Users/iwant/command-center/board-status.sh <repo> <#> "<Column>"
```

- It auto-adds the issue/PR to the board if it isn't on it yet, then sets the Status — idempotent, and it resolves IDs by name so a renamed column won't break it.
- You only set the two **label-driven** middle states: `Building` (step 2) and `In Review` (step 6). The `Closed` column is handled automatically by the board's built-in "item closed → Closed" workflow when the PR merges — you don't set it.
- This is the *only* board bookkeeping in the loop; don't add more. (Designer sets `Idea`/`Ready`; see design-queue.)

## No stacking — branch off main, merge in any order

Features branch off `main`, so they're **independent**: Tom merges open PRs in *any* order, with no chain to honor and no merge-order tree. The only exception is an issue marked `Depends on #N` — a genuine dependency or the dependent half of a foundation-first split — which simply **waits** for `#N` to merge before you pick it up. That's the whole coordination story: independent work flows freely; a real dependency is one explicit gate. Nothing is stacked, so there's no squash-vs-merge worry and nothing to keep in order.

## Cleanup on merge

A worktree and its branch are **disposable** — they exist only while the feature is in flight. Once its PR merges (Tom does that), tear both down so stale folders never pile up:

```
bash /c/Users/iwant/.claude/skills/build-loop/worktree.sh done "<repo>" "feature/<#>-<slug>"
```

This removes the worktree under `~/.worktrees/<repo>/` and deletes the local branch. Do it when you see a PR has merged (or when Tom says so) — and `worktree.sh new` always forks the *next* feature off the freshest `origin/main`, so even if local `main` wasn't pulled, new worktrees start current. Background fan-out sub-agents in `isolation: 'worktree'` are auto-cleaned by the harness, so this step is for the foreground worktrees you create.

## When two features collide at merge

The designer's bucket analysis pulls genuine shared-changes into foundation-first issues *before* you build, so most collisions never happen. If two independently-merged features still **textually conflict** (both rewrote the same lines), that's normal git — resolve it at merge: read both sides and the surrounding code, reconcile, done. It's rare and localized. If instead you spot a **semantic** surprise — a clean merge whose *behavior* is now wrong because one feature changed what another assumed — that's a review catch: flag it to Tom rather than papering over it.

## The record lives on GitHub

No worklog files, no `PROJECT-LOG.md`. The *why* goes in **issue comments**; *what shipped* is the **merged PR + closed issue**. Browsing closed issues is your shipped history — searchable, permanent, on every machine. If the **same class of decision** keeps recurring across features (each one re-deciding a leadership-only RLS predicate, say), notice it and surface to Tom that it's ripe to become written doctrine (a `DESIGN.md` / `PLAYBOOK.md`) — that distillation is its own job, not part of this loop.

## Don't over-build the system

The system is worth only what flows through it. Don't add labels, fields, or process unless real use exposes a real gap. A light loop that's shipping features beats a heavy one being tuned.
