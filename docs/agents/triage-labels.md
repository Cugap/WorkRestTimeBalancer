# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the "Label in our tracker" column to match whatever vocabulary you actually use.

## Completion state

Triage roles say whether work can start, not whether it finished. This tracker therefore has one extra status, used when work is closed:

| Label in our tracker | Meaning                                                                 |
| -------------------- | ----------------------------------------------------------------------- |
| `done`               | Every checkbox is resolved; the work is merged and verified.            |

`done` is not a triage role — a ticket leaves the triage queue and becomes `done`. Do not use `ready-for-agent` for finished work: it reads as "waiting to be picked up".

