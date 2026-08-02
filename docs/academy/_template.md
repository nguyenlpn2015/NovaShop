# Module Template

The twelve sections every Academy module carries, and what each is for. Copy this when writing
a new module.

The section order is deliberate: theory before code, code before hands, hands before judgement.

---

## 1. Learning Objectives

Three to six, each phrased as something the student can **do or explain afterwards**, not
something they will "understand". "Explain why `/live` checks no dependency" is testable.
"Understand health probes" is not.

## 2. Theory

The minimum concept needed to read the code. Keep it short — if a student needs a full tutorial
on the technology, link one in Further Reading rather than reproducing it.

**Rule:** if the theory section is longer than the walkthrough, the module has drifted into a
generic tutorial.

## 3. Repository Walkthrough

Real files, real paths, ideally real line numbers. The student opens each one.

State plainly: *if this module and the file disagree, the file is right and the module is a
bug.* Documentation drifts; that is a documented property of this repository.

## 4. Architecture Explanation

Where this fits in the whole. Link the relevant view in [`docs/architecture/`](../architecture/)
rather than redrawing it.

Answer one question explicitly: **what breaks elsewhere if this component is wrong?**

## 5. Hands-on Lab

Runnable on the student's own machine. No access to the live cluster.

Every lab ends with a verification step that can fail. A lab whose last step is "you should now
see…" teaches nothing, because the student cannot tell whether they succeeded.

## 6. Exercises

Two to four small tasks with a checkable outcome. Modifying something and re-running a gate is
the best shape — the gate is the marker.

## 7. Challenge

One larger, open-ended task with no single right answer. It should require a **decision**, and
the student should be able to defend it. Where possible, mirror a decision this repository
actually faced.

## 8. Quiz

Six to ten questions with answers below a divider. Include at least one question whose correct
answer is *"that would be wrong, and here is why"* — recognising a bad idea is a skill.

## 9. Troubleshooting

**Drawn from real defects only.** Every entry must trace to [LEARNING_LOG.md](../LEARNING_LOG.md)
or to something demonstrably true of this platform.

Format each as: symptom → what it looks like → why it is misleading → how it was found.

Invented failure scenarios are forbidden here. They teach students to recognise problems that do
not occur and miss the ones that do.

## 10. Best Practices

Practices **this repository follows**, with the file that demonstrates each. Where NovaShop
deliberately does *not* follow a common practice, say so and give the reason — those are the
most valuable entries.

## 11. Interview Questions

Three to six, cross-referenced to [`docs/interview/questions.md`](../interview/questions.md) by
number where they overlap. Do not duplicate the full answers; point at them.

## 12. Further Reading

Upstream documentation and the relevant ADRs. Two to five links. This is the one section where
material outside the repository belongs.

---

## Writing rules

**Teach from the repository.** If you find yourself explaining a concept with an invented
example, either find the real one in NovaShop or cut the concept.

**Prefer a defect to a definition.** "A scrape annotation naming the Service port produces
connection refused on every replica while nothing reports unhealthy" teaches endpoints-role
discovery better than a paragraph defining it.

**Name the trade-off.** Every design in this repository has an accepted downside recorded in an
ADR. A module that presents a decision as obviously correct is teaching the wrong lesson.

**Never claim more than the platform does.** Production Readiness is 2/5. Tracing is not
deployed. Five Terraform layers manage nothing. A module that glosses over these inherits a
credibility problem the rest of the repository does not have.
