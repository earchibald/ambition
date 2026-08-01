# Adversarial audit manifests

Two self-bootstrapping manifests for external auditors. Each is written to be handed to a
DIFFERENT model and harness than the one that wrote the code, because the point of the exercise is
to break the circularity of an implementer marking its own homework.

| Manifest | Audits | Hand to |
|---|---|---|
| `INPUT-SPEC-AUDIT-sprint3-and-3.5.md` | The SPECIFICATIONS the work was built from | Agent A |
| `OUTPUT-IMPL-AUDIT-sprint3-and-3.5.md` | The IMPLEMENTATION and its claims | Agent B |

## How to dispatch

Give each agent one instruction and nothing else:

```
/goal follow the procedure in docs/audits/INPUT-SPEC-AUDIT-sprint3-and-3.5.md
```

```
/goal follow the procedure in docs/audits/OUTPUT-IMPL-AUDIT-sprint3-and-3.5.md
```

Both manifests carry their own environment setup, branch, commands, scope boundaries, output
path, filename convention and rules of engagement. They need no further context.

## Keep them apart

The two audits have deliberately DISJOINT scope, and each manifest tells its agent to refuse the
other's findings. "The spec was vague" belongs only to the input audit; "the code does X" belongs
only to the output audit. Running them together, or letting one agent read both, collapses that
separation and you get one blurred review instead of two sharp ones.

## Filenames

Results land here as:

```
INPUT-AUDIT-RESULT--<agent-slug>--<YYYYMMDD-HHMMZ>.md
OUTPUT-AUDIT-RESULT--<agent-slug>--<YYYYMMDD-HHMMZ>.md
```

The slug identifies model AND harness (`gpt5-codex`, `gemini3-aider`). The timestamp prevents
collisions between auditors running in parallel. Both are mandatory.
