# Interview Curriculum

Everything needed to explain NovaShop confidently, grounded entirely in what this repository
actually contains. No generic DevOps material.

## The four documents

| Document | Use when |
|---|---|
| [Repository Guide](repository-guide.md) | Learning or re-learning the platform end to end |
| [Question Bank](questions.md) | 107 questions across five levels, with answers, reasoning, common mistakes, and follow-ups |
| [Cheat Sheets](cheatsheets.md) | The night before, the morning of, and the five minutes before |
| [../INTERVIEW_GUIDE.md](../INTERVIEW_GUIDE.md) | The ten-minute live demo script |

The short guide at `docs/INTERVIEW_GUIDE.md` is the **demo**. This directory is the
**preparation**. They do not duplicate each other.

## How to use this

**Two weeks out.** Read [Repository Guide](repository-guide.md) once. Then, for each
subsystem, open the actual file it describes and check the guide is telling the truth. If it
is not, fix the guide — that is a better use of an hour than re-reading it.

**One week out.** Work through [Question Bank](questions.md) at your level and one level
above. Answer out loud before reading the answer.

**The night before.** [Cheat Sheets](cheatsheets.md), one-page revision notes.

**Thirty minutes before.** The 30-minute preparation section.

**Five minutes before.** The elevator pitch.

## The one rule

**Never claim something this repository does not do.**

The platform's credibility comes from its own audit scoring Production Readiness 2/5 and its
release notes leading with limitations. That advantage disappears the moment you oversell in
a room. Every answer in the question bank is written to be true.

The four things to state before an interviewer finds them:

1. The application has **no schema and no business endpoints**. The database has zero tables.
2. **Distributed tracing is instrumented and not deployed** — [ADR 011](../../adr/011-distributed-tracing.md).
3. **Five of seven Terraform layers manage nothing** — the interface is designed, the
   resources are not written.
4. **Alerts route nowhere.** They evaluate and are queryable; nothing pages anyone.

Each is in [AUDIT.md](../AUDIT.md) with a score attached. Naming your own gaps is what makes
the rest believable.
