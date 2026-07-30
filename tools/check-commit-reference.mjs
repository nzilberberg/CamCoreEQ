#!/usr/bin/env node
// GATE (commit-msg): a change to a subsystem the sibling reference project already
// solved must CITE what that reference does.
//
// Three times now, a subsystem here was designed from scratch while TomeRoam -- a
// working, device-proven sibling on the same disk -- already had a better answer, and
// the user had to ask "what does TomeRoam do?" each time. A rule to "remember to check"
// is vigilance. This refuses the commit instead.
//
// It fires only for changes touching the reference-shared surface (the Android shell,
// the update manifest, and the page's own update/bridge plumbing). To satisfy it, put a
// line in the commit message:
//
//   Reference: TomeRoam <file> does X -- following it / diverging because Y
//   Reference: n/a -- <why the reference has no bearing>
//
// Usage: node tools/check-commit-reference.mjs <commit-msg-file>
// Exit 0 pass / 1 refuse / 2 could not run (fails closed).

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const msgFile = process.argv[2];
if (!msgFile) { console.error("GATE ERROR: no commit-message file given"); process.exit(2); }

const repoRoot = path.resolve(new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));

// Strip git's location vars: this runs FROM a hook, and an ambient GIT_DIR overrides cwd.
const env = { ...process.env };
for (const k of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX",
                 "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
                 "GIT_ALTERNATE_OBJECT_DIRECTORIES"]) delete env[k];

let staged;
try {
  staged = execFileSync("git", ["diff", "--cached", "--name-only", "--diff-filter=ACM"],
                        { cwd: repoRoot, env, encoding: "utf8" }).split("\n").filter(Boolean);
} catch (e) { console.error("GATE ERROR: git diff --cached failed: " + e.message); process.exit(2); }

// The surface where the reference has a proven implementation.
const GUARDED = [
  { re: /^android\//,      why: "the Android shell" },
  { re: /^build\.json$/,   why: "the update manifest" },
];
const touched = staged.filter((f) => GUARDED.some((g) => g.re.test(f)));

// index.html only counts when the change is in its update/bridge plumbing, not for an
// EQ or styling edit -- otherwise the gate would nag on every unrelated page tweak and
// get worked around, which is how a gate dies.
if (staged.includes("index.html")) {
  let diff = "";
  try { diff = execFileSync("git", ["diff", "--cached", "-U0", "--", "index.html"],
                            { cwd: repoRoot, env, encoding: "utf8" }); } catch {}
  const changed = diff.split("\n").filter((l) => /^[+-]/.test(l) && !/^([+-][+-][+-])/.test(l)).join("\n");
  if (/CamCoreEQNative|EQ_NATIVE|checkNow|stagedWebBuild|applyWebUpdate|updateApp|__webbuild|visibilitychange/.test(changed)) {
    touched.push("index.html (update/bridge plumbing)");
  }
}

if (!touched.length) process.exit(0);

let msg = "";
try { msg = fs.readFileSync(msgFile, "utf8"); } catch { console.error("GATE ERROR: cannot read " + msgFile); process.exit(2); }
const body = msg.split("\n").filter((l) => !l.startsWith("#")).join("\n");

if (/^\s*Reference:\s*\S/mi.test(body)) process.exit(0);

console.error("COMMIT REFUSED - this change touches a reference-shared subsystem:");
for (const t of touched) console.error("    " + t);
console.error("");
console.error("TomeRoam already implements these, on a real device. Consult it first:");
console.error("    node tools/reference-check.mjs update|apk|bridge|webview|insets|build|sw");
console.error("");
console.error("Then add a Reference: line to the commit message, e.g.");
console.error("    Reference: TomeRoam re-checks via visibilitychange in the web layer, not a");
console.error("               native timer -- following that.");
console.error("    Reference: n/a -- <why the reference has no bearing here>");
process.exit(1);
