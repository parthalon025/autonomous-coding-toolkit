#!/usr/bin/env node
'use strict';

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Toolkit root: works for npm global, npx, and local clone
// ---------------------------------------------------------------------------
const TOOLKIT_ROOT = path.resolve(__dirname, '..');
let VERSION;
try {
  const pkg = JSON.parse(fs.readFileSync(path.join(TOOLKIT_ROOT, 'package.json'), 'utf8'));
  VERSION = pkg.version;
} catch (err) {
  console.error('Error: Could not read package.json');
  console.error(`  ${err.message}`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Platform check — bash required
// ---------------------------------------------------------------------------
function checkPlatform() {
  if (process.platform === 'win32') {
    let inWsl = false;
    try {
      inWsl = fs.existsSync('/proc/version') &&
        fs.readFileSync('/proc/version', 'utf8').toLowerCase().includes('microsoft');
    } catch (_) {
      // If /proc/version is unreadable, assume not WSL
    }
    if (!inWsl) {
      console.error(
        'Error: act requires bash, which is not available on native Windows.\n' +
        'Hint: Install WSL2 (https://aka.ms/wsl) and run act from a WSL terminal.'
      );
      process.exit(1);
    }
  }
}

// ---------------------------------------------------------------------------
// Dependency check
// ---------------------------------------------------------------------------
function checkDep(cmd) {
  try {
    execFileSync('which', [cmd], { stdio: 'pipe' });
  } catch (_) {
    console.error(`Error: Required dependency "${cmd}" not found on PATH.`);
    console.error(`Install it and try again.`);
    process.exit(1);
  }
}

function checkDependencies() {
  checkDep('bash');
  checkDep('git');
  checkDep('jq');
}

// ---------------------------------------------------------------------------
// Script runner
// ---------------------------------------------------------------------------
function scripts(name) {
  return path.join(TOOLKIT_ROOT, 'scripts', name);
}

function runScript(scriptPath, args) {
  if (!fs.existsSync(scriptPath)) {
    console.error(`Error: Script not found: ${scriptPath}`);
    console.error('This script may not be included in the current installation.');
    console.error('Try reinstalling: npm install -g autonomous-coding-toolkit');
    process.exit(1);
  }
  try {
    execFileSync('bash', [scriptPath, ...args], { stdio: 'inherit' });
  } catch (err) {
    process.exit(err.status != null ? err.status : 1);
  }
}

// ---------------------------------------------------------------------------
// Help text
// ---------------------------------------------------------------------------
function printHelp() {
  console.log(`Autonomous Coding Toolkit v${VERSION}

Usage: act <command> [options]

Execution:
  plan <file> [flags]          Headless/team/MAB batch execution
  plan --resume                Resume interrupted execution
  compound [dir]               Full pipeline: report→PRD→execute→PR
  mab <flags>                  Multi-Armed Bandit competing agents

Quality:
  gate [flags]                 Composite quality gate (lesson-check + tests + memory)
  check [files...]             Syntactic anti-pattern scan from lesson files
  policy [files...]            Advisory positive-pattern checker
  research-gate [flags]        Block PRD if unresolved research issues
  validate                     Run all validators
  validate-plan <file>         Validate plan quality score
  validate-prd [file]          Validate PRD shell-command criteria

Lessons:
  lessons pull                 Pull community lessons from upstream
  lessons check                List active lesson checks
  lessons promote              Promote MAB-discovered lessons
  lessons infer                Infer scope metadata for lesson files

Analysis:
  audit [flags]                Entropy audit: doc drift, naming violations
  batch-audit [flags]          Cross-project audit runner
  batch-test [flags]           Memory-aware cross-project test runner
  analyze [report]             Analyze audit/test report
  digest [flags]               Failure digest from run logs
  status [flags]               Pipeline status summary
  architecture [flags]         Generate architecture map

Telemetry:
  telemetry [flags]            Telemetry reporting

Benchmarks:
  benchmark [flags]            Run benchmark suite

Setup:
  init [flags]                 Initialize toolkit in current project
  license-check [flags]        Check dependency licenses
  module-size [flags]          Check module sizes against budget

Meta:
  version                      Print version
  help                         Show this help text
`);
}

// ---------------------------------------------------------------------------
// Command map
// ---------------------------------------------------------------------------
const COMMANDS = {
  // Execution
  plan:            { script: scripts('run-plan.sh') },
  compound:        { script: scripts('auto-compound.sh') },
  mab:             { script: scripts('mab-run.sh') },

  // Quality
  gate:            { script: scripts('quality-gate.sh') },
  check:           { script: scripts('lesson-check.sh') },
  policy:          { script: scripts('policy-check.sh') },
  'research-gate': { script: scripts('research-gate.sh') },
  validate:        { script: scripts('validate-all.sh') },
  'validate-plan': { script: scripts('validate-plan-quality.sh') },
  'validate-prd':  { script: scripts('validate-prd.sh') },

  // Analysis
  audit:           { script: scripts('entropy-audit.sh') },
  'batch-audit':   { script: scripts('batch-audit.sh') },
  'batch-test':    { script: scripts('batch-test.sh') },
  analyze:         { script: scripts('analyze-report.sh') },
  digest:          { script: scripts('failure-digest.sh') },
  status:          { script: scripts('pipeline-status.sh') },
  architecture:    { script: scripts('architecture-map.sh') },

  // Setup
  init:            { script: scripts('init.sh') },
  'license-check': { script: scripts('license-check.sh') },
  'module-size':   { script: scripts('module-size-check.sh') },

  // Telemetry
  telemetry:       { script: scripts('telemetry.sh') },

  // Benchmarks (note: under benchmarks/, not scripts/)
  benchmark:       { script: path.join(TOOLKIT_ROOT, 'benchmarks', 'runner.sh') },
};

// Lessons sub-dispatch
const LESSONS_COMMANDS = {
  pull:    { script: scripts('pull-community-lessons.sh'), args: [] },
  check:   { script: scripts('lesson-check.sh'),          args: ['--list'] },
  promote: { script: scripts('promote-mab-lessons.sh'),   args: [] },
  infer:   { script: scripts('scope-infer.sh'),           args: [] },
};

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];
  const rest = args.slice(1);

  // Built-in meta commands (no bash needed)
  if (!cmd || cmd === 'help' || cmd === '--help' || cmd === '-h') {
    printHelp();
    process.exit(0);
  }

  if (cmd === 'version' || cmd === '--version' || cmd === '-v') {
    console.log(`act v${VERSION}`);
    process.exit(0);
  }

  // Platform + dependency checks for all other commands
  checkPlatform();
  checkDependencies();

  // Lessons sub-dispatch
  if (cmd === 'lessons') {
    const sub = rest[0];
    const subArgs = rest.slice(1);
    if (!sub) {
      console.error('Error: "lessons" requires a subcommand: pull, check, promote, infer');
      process.exit(1);
    }
    const lessonCmd = LESSONS_COMMANDS[sub];
    if (!lessonCmd) {
      console.error(`Error: Unknown lessons subcommand: ${sub}`);
      console.error('Available: pull, check, promote, infer');
      process.exit(1);
    }
    runScript(lessonCmd.script, [...lessonCmd.args, ...subArgs]);
    return;
  }

  // Standard command routing
  const entry = COMMANDS[cmd];
  if (!entry) {
    console.error(`Error: Unknown command: ${cmd}`);
    console.error(`Run "act help" to see available commands.`);
    process.exit(1);
  }

  runScript(entry.script, rest);
}

main();
