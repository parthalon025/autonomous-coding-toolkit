# Changelog

## [1.1.0](https://github.com/parthalon025/autonomous-coding-toolkit/compare/v1.0.0...v1.1.0) (2026-03-22)


### Features

* add benchmark suite with 5 tasks and runner.sh ([42608fc](https://github.com/parthalon025/autonomous-coding-toolkit/commit/42608fc4e1d71e0b57b550ecb682e67b4afeab61))
* add bin/act.js CLI router for npm distribution ([2abb0dd](https://github.com/parthalon025/autonomous-coding-toolkit/commit/2abb0dd11d48b7c451dd41c3bb0fdcd80c48b6c4))
* add init.sh project bootstrapper with quickstart mode ([7701a47](https://github.com/parthalon025/autonomous-coding-toolkit/commit/7701a47fb51f9b6d550c9df517e982b546e76592))
* add install.sh for global skill/agent/command symlinks ([ad87c3f](https://github.com/parthalon025/autonomous-coding-toolkit/commit/ad87c3f929fee09cc76d1184568a4c289b6c0f89))
* add module-size-check.sh with quality gate integration ([46e3b81](https://github.com/parthalon025/autonomous-coding-toolkit/commit/46e3b81027b02af50c634cfc8511169e29211ca6))
* add package.json for npm distribution ([7ebd6b8](https://github.com/parthalon025/autonomous-coding-toolkit/commit/7ebd6b8f8d95606fc5d972221cd302d7cadda79b))
* add post-commit evaluator for heeded/recurrence outcome recording ([dd21346](https://github.com/parthalon025/autonomous-coding-toolkit/commit/dd2134617c47749b7bce146339c2df55d62d0deb))
* add telemetry.sh — capture, dashboard, export, reset ([663be17](https://github.com/parthalon025/autonomous-coding-toolkit/commit/663be17d86f999161e6f4e99b93a8c4d69ca75d3))
* add Tier 2 semantic echo-back via LLM verification ([609074e](https://github.com/parthalon025/autonomous-coding-toolkit/commit/609074ea8918cbf5afd10f068b0e0bcef6c6fd76))
* add trust score computation to telemetry ([146209e](https://github.com/parthalon025/autonomous-coding-toolkit/commit/146209e862b9d9af0fedbb352a35c6f1843c6c10))
* auto-install CLI commands via SessionStart hook ([e82f8b7](https://github.com/parthalon025/autonomous-coding-toolkit/commit/e82f8b7f6661e9a0db3998d7a0551db415a88bec))
* display trust score in pipeline status ([51d8e58](https://github.com/parthalon025/autonomous-coding-toolkit/commit/51d8e5887c1a8cc3add2dfff359d3634f1aa09e9))
* integrate telemetry capture into quality gate pipeline ([f48cb94](https://github.com/parthalon025/autonomous-coding-toolkit/commit/f48cb94bac0583a4631d50aa432d78bd05788279))
* lesson-check refactor + lessons-db integration ([85d7641](https://github.com/parthalon025/autonomous-coding-toolkit/commit/85d7641f9a3e03b317776ec7e42c18d422461574))
* lesson-check refactor + lessons-db integration ([2ce4a50](https://github.com/parthalon025/autonomous-coding-toolkit/commit/2ce4a50b6ccd07d183c81a8385ab749db53abe45))
* make lessons-db the primary source for lesson-check; add post-commit auto-import hook ([eccd8f0](https://github.com/parthalon025/autonomous-coding-toolkit/commit/eccd8f0aeb1cc2d72af6987c790db0b6fec4584d))
* Phase 5B+5C+6 — onboarding, 12 new lessons, pipeline extensions ([3171f00](https://github.com/parthalon025/autonomous-coding-toolkit/commit/3171f0042c24f8a1ad9e7d91507ec783beac2338))
* support ACT_ENV_FILE in telegram.sh for portable installs ([1b4637c](https://github.com/parthalon025/autonomous-coding-toolkit/commit/1b4637c86de4baa72045f2384b66a27d819417da))
* support project-local lessons (Tier 3) in lesson-check.sh ([e30143d](https://github.com/parthalon025/autonomous-coding-toolkit/commit/e30143d8675f828ddd20980b4a2ccd8cbfe1253a))


### Bug Fixes

* correct superpowers attribution URL in README ([6956387](https://github.com/parthalon025/autonomous-coding-toolkit/commit/6956387b73e6c7243bcca9221f23ae0c8da2b1b3))
* evaluator requests only unknown-outcome events ([628f05f](https://github.com/parthalon025/autonomous-coding-toolkit/commit/628f05f0fc81133979a8ec8ac7b6e03cebdb5499))
* harden bin/act.js error handling — package.json read, WSL check, exit codes ([ccf8748](https://github.com/parthalon025/autonomous-coding-toolkit/commit/ccf87480d1ad770d4496a82b19c47cc022144fae))
* harden telemetry.sh numeric inputs + test jq assertion ([7c0a9dc](https://github.com/parthalon025/autonomous-coding-toolkit/commit/7c0a9dc0740ec41bbfc049bce5042057e46d5f40))
* isolate lesson-check tests from toolkit's own package.json ([0a2f8f9](https://github.com/parthalon025/autonomous-coding-toolkit/commit/0a2f8f99bd08d8863f777731bae69384a8ee65b8))
* prevent duplicate lesson scans when PROJECT_ROOT is toolkit root ([269838a](https://github.com/parthalon025/autonomous-coding-toolkit/commit/269838a65f544e230e70d02ff391050409552060))
* quote $PROJECT_ROOT in init.sh output + add failure test ([ba9ec5e](https://github.com/parthalon025/autonomous-coding-toolkit/commit/ba9ec5e0878e1236de9d72f074172a970f150c03))
* resolve path bugs in quality gate default and MAB runner ([#73](https://github.com/parthalon025/autonomous-coding-toolkit/issues/73)) ([d38d618](https://github.com/parthalon025/autonomous-coding-toolkit/commit/d38d6185f4c63711776693cccc60316d0f15a5ee))
* skip meta-files in post-commit lessons-db auto-import ([8786685](https://github.com/parthalon025/autonomous-coding-toolkit/commit/878668543741d38ebd08a05e05dc59dadeadf3f1))
* use correct lessons-db check --files flag in evaluator ([ff25e81](https://github.com/parthalon025/autonomous-coding-toolkit/commit/ff25e81fe968853ed26061ba1f7cb36cf343cf30))
