// Conventional Commits enforcement
// https://www.conventionalcommits.org/
export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "type-enum": [
      2,
      "always",
      [
        "feat",
        "fix",
        "docs",
        "style",
        "refactor",
        "perf",
        "test",
        "build",
        "ci",
        "chore",
        "revert",
        "setup",
      ],
    ],
    "subject-case": [0], // Allow any case in subject
    "body-max-line-length": [0], // Allow long body lines
  },
};
