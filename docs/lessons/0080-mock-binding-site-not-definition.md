---
id: "0080"
title: "Mock the binding site, not the definition site"
severity: blocker
languages: [python]
category: test-anti-patterns
pattern:
  type: semantic
  description: >
    When a function is imported with `from module import func` and then called
    inside another module, tests that patch `module.func` (the definition site)
    leave the importing module's local binding untouched. The mock never intercepts
    the call, and the test passes using the real function — giving false confidence.
    Always patch `importing_module.func`, not `module.func`.
fix: >
    Patch where the name is *used*, not where it is *defined*.
    If `judge.py` does `from client import call_judge`, tests must patch
    `mypackage.judge.call_judge` — not `mypackage.client.call_judge` and not
    the `__init__` re-export. The rule: find the `from X import Y` line in the
    file under test; the patch target is `that_file_module.Y`.
example:
  bad: |
    # client.py
    def call_judge(prompt): ...

    # judge.py
    from client import call_judge   # creates local binding

    def run_eval_judge(...):
        response = call_judge(prompt)  # calls LOCAL binding

    # test_judge.py — WRONG: patches definition site, not binding site
    with patch("mypackage.client.call_judge") as mock:
        mock.return_value = '{"transfer": 5}'
        run_eval_judge(...)  # real call_judge still called — mock never fires
        assert mock.called   # PASSES even though mock was never invoked
  good: |
    # test_judge.py — CORRECT: patches the local binding in judge.py
    with patch("mypackage.judge.call_judge") as mock:
        mock.return_value = '{"transfer": 5}'
        run_eval_judge(...)
        assert mock.called   # actually verified
---

## Observation

A test suite for an eval pipeline had 14 tests patching `lessons_db.eval.call_judge`
(the re-export path) instead of `lessons_db.eval.judge.call_judge` (where the name
is bound in `judge.py`). All 14 tests passed, but the real `call_judge` was being
invoked on each run — making network calls to Ollama when Ollama was available, and
failing silently when it wasn't. The mock was a no-op. A second related bug —
`build_paired_judge_prompt` also patched at the wrong path — caused an `IndexError`
from an empty list that was never populated by the real function.

## Insight

Python's import system is name-binding, not reference-passing. `from X import Y`
copies the *reference* to `Y` into the current module's namespace as a new name.
Patching `X.Y` replaces the name in module `X`, but the importing module already
holds its own reference and won't see the change. The mock and the function-under-test
are looking at different bindings.

`unittest.mock.patch` works by attribute substitution on a module object: it finds
the module by dotted path and sets an attribute on it. If you give it the wrong module,
it patches a binding nobody reads.

## Lesson

**Before writing any `patch()` call:** find the `from X import Y` line in the file
you're testing. The patch target is always `<that_file_as_dotted_module_path>.Y`.
Never patch `__init__.py` re-exports — those are aliases; the actual binding is in
the leaf module. When in doubt, add a `print(call_judge)` inside the test to confirm
the mock is actually the object being called.
