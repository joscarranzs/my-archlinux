# caveman-shrink

Deterministic compressor for the `terminal` tool's output. It rewrites noisy
results (log dumps, systemd tables, test runs, JSON arrays) into a summary before
the model reads them, then appends a footer saying what it did:

```
[caveman-shrink: tests · 3191 -> 99 tok (9572 -> 297 bytes). Full text: /home/u/.hermes/cache/terminal-output/caveman-1794815773-612303-tests.log]
```

That path always exists. Hermes only spills an overflow copy when the capture
blows past its own ceiling, so the plugin writes the untouched text itself and
prints where it landed, or says plainly that it could not.

The idea is caveman's "read less" rock, reimplemented on Hermes' own seam. Caveman
ships that compressor inside its Go proxy because the Claude/Codex hook APIs
cannot rewrite tool output; Hermes can, through `transform_terminal_output`.

## Contract

`transform_terminal_output` fires inside the `terminal` tool after foreground
capture and before the final output limit. A string replaces what the model
reads; `None` leaves the output alone. The hook also fires for
`process_manage` poll/wait/log/kill results and their notifications.

The replacement is still subject to Hermes' output limit and is redacted
afterwards like any other output.

## Rules it obeys

1. **Payload is verbatim.** Error lines, tracebacks, file paths, test summaries,
   counts and exit status are copied character for character. Tests cover the
   case that matters: a real failure buried in 160 passing tests survives with
   its assertion message.
2. **Fail open.** Unknown shape, ambiguous format, broken JSON, thin win, or any
   exception returns `None` and the original reaches the model. Below 4096 bytes
   it does nothing: a summary costs more attention than it saves.
3. **It never touches a command or an exit code.** Only the text after the run.
4. **The footer never lies.** A path in the footer is a file you can open. If the
   copy cannot be written, the footer says the text was not saved and how to get
   it back, instead of pointing at nothing.

## What it recognises

| Shape | Kept |
|---|---|
| Logs (journal, app logs) | Lines with uppercase severity, tracebacks, `File "…", line N`, failures, ±2 lines of context; consecutive repeats collapsed as `(xN)` |
| systemd-style tables | Header, tally of ACTIVE states, only the rows that are not loaded+active+(running\|exited\|mounted…) |
| Test output | Failures, tracebacks and the `Ran N tests` / `OK` / `FAILED` summary |
| JSON arrays of objects | Count, key list, head/tail sample |
| Anything else | Nothing — passes through untouched |

A summary is capped at 12 KB; when it overflows, the oldest spans go first and
the footer says how many.

## Install / disable

```bash
hermes plugins list | grep caveman-shrink      # status
hermes plugins disable caveman-shrink          # off, keeps the files
hermes plugins enable caveman-shrink           # back on
python3 -m unittest discover -s tests          # 27 tests
hermes plugins validate ~/.hermes/plugins/caveman-shrink
```

No network, no state, stdlib only, one hook, no tools.
