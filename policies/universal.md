# Universal Policies

Cross-language positive patterns. These apply to all projects regardless of language.

## Error Visibility

**Always log before returning a fallback value.**
When a function catches an error and returns a default, the error must be logged first. Silent fallbacks hide bugs.

```
# Pattern: catch → log → fallback
try:
    result = fetch_data()
except ConnectionError as e:
    logger.warning("fetch_data failed, using cache: %s", e)
    result = cached_value
```

## Test Before Ship

**Run the full test suite before claiming work is complete.**
Partial test runs miss integration failures. "It works on my machine" is not verification.

```
# Pattern: test → verify → commit
make ci          # or: pytest / npm test / make test
git add <files>
git commit
```

## Fresh Context Per Unit

**Start each independent unit of work with a clean context.**
Context degradation compounds — stale variables, wrong assumptions, and accumulated state cause subtle bugs after extended sessions.

```
# Pattern: checkpoint → clear → resume
# After 5+ batches or major topic shift, start fresh
```

## Append-Only Progress

**Never overwrite progress files — always append.**
Truncating progress loses discoveries from prior batches. The next context reset will repeat mistakes.

```
# Pattern: append to progress.txt
echo "## Batch 3: Added auth middleware" >> progress.txt
```

## Durable Artifacts

**Every research activity produces a file, not just conversation.**
Conversation context resets; files persist. If it's worth investigating, it's worth writing down.

```
# Pattern: investigate → write file → reference file
# Bad: "I looked into it and found..."
# Good: Write findings to tasks/research-<slug>.md
```
