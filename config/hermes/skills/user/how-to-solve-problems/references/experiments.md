# Bounded experiments

## Shape of a probe

1. Write the hypothesis in one sentence.
2. Name the single variable it changes.
3. Name the cheapest observation that falsifies it.
4. Decide rollback before running.
5. Run it; record command and exact output.
6. Keep the result, pass or fail, in the log.

One variable per probe. A probe that changes three things proves nothing about any of them.

## Silent failures worth probing

- A lookup that returns a plausible answer for every input cannot report a miss. Feed it a name you know is invalid and inspect the rendered result.
- A guard on a truthy value is dead code if the value is never empty. Print the value before trusting the guard.
- An undefined field, role or flag can fall back to a default without an error. Diff what a component reads against what its provider declares.
- A change to environment config may not take effect until restart. Check the running process, not only the file.
- An async answer can swap one frame later. Sample at the frame the user sees, then one frame after.
- A type that is not a string (`url`, enum, null) breaks equality checks. Inspect the real type before comparing.
- A stubbed harness can start in a loading state. Assert on the settled state.

## Stop rules

- Two iterations with no new information: stop, report the unknown and the artifact needed.
- A fix that works for reasons you cannot state: do not ship it as understood.
- An experiment with an unrecoverable side effect: do not run it without authorization.
- Costs climb faster than insight: switch to the cheapest sufficient route or report blocked.
