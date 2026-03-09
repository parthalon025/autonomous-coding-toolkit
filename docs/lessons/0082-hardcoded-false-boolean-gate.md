---
id: "0082"
title: "Hardcoded false boolean gate silently freezes UI state forever"
severity: should-fix
languages: [javascript, typescript]
category: silent-failures
pattern:
  type: syntactic
  regex: "(?:const|let|var)\\s+\\w*[Cc]omplete\\w*\\s*=\\s*false\\s*;"
  description: >
    A completion/progress boolean is hardcoded to `false` (often as a TODO
    placeholder when the real check couldn't be implemented yet). Any UI that
    gates on this variable — checklists, wizards, stepper flows — will permanently
    show that step as incomplete, and all downstream gates that depend on it will
    also be stuck. There is no error, no warning, and no indication to the user
    that anything is wrong.
fix: >
    Never commit hardcoded `false` as a completion gate. Either implement the
    real check, or remove the step entirely. If the check is genuinely
    impossible to automate, replace the gate with a user-acknowledged boolean
    stored in settings/localStorage: `const step2Complete = settings['step2_confirmed'] === true`.
    This makes progress explicit rather than permanently blocked.
example:
  bad: |
    // SetupChecklist.jsx
    const step1Complete = step1Status === 'ok';
    const step2Complete = false;  // TODO: can't auto-detect, leave for now
    const step3Complete = step2Complete && variants.length > 0;
    const step4Complete = step3Complete && runs.length > 0;
    // Result: step3 and step4 are ALWAYS false, even when the user has done everything.
    // The checklist is permanently stuck at "step 2" with no indication why.
  good: |
    // Option A: Remove the step if it can't be automated
    const step1Complete = step1Status === 'ok';
    const step2Complete = step1Complete && runs.length > 0;

    // Option B: Make it user-confirmed via persisted settings
    const step2Complete = step1Complete && settings['models_verified'] === true;
    // ... show a "Mark as done" button that saves settings['models_verified'] = true
---

## Observation

A 4-step setup checklist in the eval pipeline UI had `const step2Complete = false`
hardcoded as a placeholder. Step 2 was meant to verify that Ollama models were
installed, but there was no reliable way to auto-check this from the frontend. The
developer left it as `false` intending to return to it. Steps 3 and 4 were gated on
`step2Complete`, so the entire checklist was permanently frozen at step 2 — even for
users who had done everything correctly and run multiple eval sessions. The component
showed no error; it simply never advanced. The bug went unnoticed because the checklist
auto-hides once `setup_complete` is saved in settings — users who had already
completed setup never saw it again.

## Insight

Boolean gates in sequential UI flows create a dependency chain. A single permanent
`false` anywhere in the chain locks every downstream state. Unlike a runtime error
or a visible "broken" state, a hardcoded `false` looks exactly like legitimate
"not done yet" state — making it nearly impossible to debug from the UI alone.

The danger compounds when the gated behavior auto-hides on completion: existing users
never hit the bug, so it stays in the codebase untested indefinitely. New users hit
a permanently broken onboarding experience.

## Lesson

Treat `= false` as a code smell whenever it appears as a step/completion/gate
variable. Before committing any multi-step flow, verify every completion variable
has a real runtime condition — not a hardcoded constant. If you genuinely cannot
automate a check, either remove the step or replace the hardcode with a
user-confirmed setting that persists to storage. A TODO comment next to `= false`
does not make it safe to ship.
