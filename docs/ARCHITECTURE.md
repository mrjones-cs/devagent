# Why DevAgent is built the way it is

The decisions behind the shape of the system, and the evidence for each.
[DESIGN.md](DESIGN.md) is the normative specification; this explains it.

## 1. Resident rules versus on-demand skills

Claude Code loads `~/.claude/CLAUDE.md` on every turn. Plugins cannot ship
always-on instructions (the plugin format has `skills/`, `agents/`, `hooks/`,
`commands/` and `.mcp.json`, but no plugin-level `CLAUDE.md`), so resident
rules have to be a file that `install.sh` places, and everything else is a
skill that loads when the work matches its description.

Putting everything resident does not work. The problem is not token cost
(a 20k-token rules file is about 2% of a 1M context window) but **attention
dilution**: long checklists get skimmed rather than applied. A rule that is
present but skimmed is worse than one that loads in full at the moment it
applies.

One test decides where each rule lives:

> Is the trigger self-evident from the task, or is the failure mode *not
> noticing*?

- **Trigger self-evident → skill.** "I am building a login", "I am
  generating a PDF", "I am provisioning cloud infrastructure" are
  unmistakable, so the detail can load on demand and arrive complete.
- **Failure mode is not noticing → resident.** A prohibition cannot be
  enforced by a file that only loads once you have recognised it applies.

Skills load by description match, which is probabilistic. So **every skill
has a resident stub that names it** (`**`devagent-standards:<skill>`** — summary.
→ Invoke when …`): the stub is the deterministic trigger, the skill is the
detail. `check-skills.py` fails if a skill has no stub.

| Stays resident | Why it cannot load on demand |
| --- | --- |
| Browser automation on identity surfaces | A skill cannot stop the agent reaching for a tool |
| Agent and developer toolchain security | Injection arrives in content being read *before* any trigger fires |
| Verification | Fires when about to claim done, exactly when a skill would not be invoked |
| Customer confidentiality, content constraints | Govern every outbound token, every turn; the ban must be in force before drafting |
| Incident response (leaked credentials) | Discovery can happen on any turn, in any file |
| The OWASP screening rule | The *rule* is resident; the checklist is a reference file |

## 2. Exactly two HIGHEST PRIORITY sections

A priority label on many sections flattens the very signal it exists to
create. The template marks two, chosen by a stricter test than importance:
**does the failure reverse?** Disclosed build knowledge cannot be recalled
(customer confidentiality), and a compromised workstation reaches every
engagement at once (toolchain security). Everything else is mandatory but
recoverable. The template forbids a third, so whoever adds one has to argue
with it.

## 3. Rules about behaviour, not tool names

An early version of the browser rule banned one automation tool by name,
while another, with the same capability, was loadable and attached to the
signed-in browser by default. The rule could be obeyed literally while
reproducing the incident it existed to prevent. So the rule is written
against the **behaviour** (never drive a session carrying the user's
identity across an account, billing or security surface) and names tools
only as examples. A prohibition written against a tool name does not survive
a new tool with the same capability.

## 4. Guard hooks: prose rules with a deterministic backstop

Every toolchain rule is a sentence the model is trusted to follow, and an
injected instruction targets exactly that trust. `devagent-guard` runs on
every tool call, outside the model, so the most important rules fire
whether or not the model remembers them.

- **Enforce by default, after evidence.** A noisy guard gets switched off,
  which is worse than none. The guard shipped warn-only first; the switch to
  enforce came after a review of real traffic (`scripts/guard-report.py`)
  showed nothing enforce mode would have wrongly denied.
- **Fail open, never silently.** A crashed guard must not brick the agent,
  so an internal error lets the call through but is reported and recorded as
  a `hook_error`.
- **Parse like a shell, conservatively.** Command splitting respects quotes
  (a commit message naming a blocked pattern is data), while anything a shell
  executes, such as `sh -c`, `eval`, `$(…)`, backticks and heredoc bodies, is
  still checked. When parsing is uncertain (unbalanced quotes) it falls back
  to the strict split.
- **A typo cannot disable it.** Only an exact `DEVAGENT_GUARD_MODE=warn`
  rolls back; any other value means the shipped default.
- **Not a sandbox.** Stated plainly in the README, so nobody mistakes it for
  one.

## 5. The workflow writes markdown, in git

Every delivery step writes a file in `docs/plans/<feature>/`. A database or
vector store would hide the record from review, add a data store to secure
and destroy, and (for a shared index) cross-contaminate projects by design.
Git is already the review, history and access-control system. The plan
grammar (`delivery-plan/1`) is checked by `check-plan.py` in CI, by a hook as
files are written, and by the build before it starts.

## 6. The model never types evidence

A task is ticked only with an evidence line that `run-verify` wrote: it runs
an allowlisted command without a shell, with AWS and GitHub credentials
stripped from the environment, writes the full log, hashes it, and treats a
run that reports zero tests as a failure, because a filter that matched
nothing proves nothing. `check-plan.py` verifies each log against its hash.

## 7. Scope is checked before anything runs

`build-integrate` compares a task's changed paths with its declared `files`
before any code from the task's branch is executed, then verifies it in the
task's own worktree against the plan as committed on `main`, and squashes it
with the tick in one commit. Changes to CI, agent configuration, hooks or
dependency manifests stop for explicit approval. The build never pushes.

## 8. Research is a separate trust zone

Fetched pages and search results are untrusted text. The researcher agent
gets only the assumption rows it is checking, never the whole design; it can
read, fetch and run one search script; the guard limits fetches to official
documentation domains while research is active; and a per-project deny-list
is checked before any query leaves the machine. A search excerpt is a lead,
never a source: a fact is confirmed only on the official page.

## 9. The session briefing is structure only

A SessionStart hook gives each session a short briefing. It contains IDs,
statuses and counts, never free text from a plan, notes or knowledge file,
because free text there would be an injection path into every session start.
The full, labelled-as-data briefing is `/delivery:load`.

## 10. Workflow steps are user-invoked only

Every delivery skill sets `disable-model-invocation: true`. A workflow step
is a deliberate act by the operator, which keeps a deterministic trigger and
stops the model starting a build on its own initiative.
