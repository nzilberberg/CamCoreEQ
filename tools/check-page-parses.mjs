#!/usr/bin/env node
// GATE: index.html's inline JavaScript must parse, or the commit is refused.
//
// Why this exists: a sed edit ate a backslash in a regex literal (`/; wv\)/` became
// `/; wv)/`), and because the whole app lives in ONE inline <script> block, that
// single SyntaxError killed EVERY feature on the page -- and the build was deployed
// to the player and published for OTA without anyone loading it. A page that cannot
// parse must never be committable, let alone deployable.
//
// Usage:  node tools/check-page-parses.mjs [file...]     (default: index.html)
// Exit 0 = all script blocks parse. 1 = a block fails. 2 = the gate could not run
// or found no script at all (fails closed -- scanning nothing is never a pass).

import fs from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
const files = process.argv.slice(2).length
  ? process.argv.slice(2)
  : [path.join(repoRoot, "index.html")];

let fail = 0, blocks = 0;
for (const f of files) {
  let html;
  try { html = fs.readFileSync(f, "utf8"); }
  catch (e) { console.error("GATE ERROR: cannot read " + f); process.exit(2); }

  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  if (!scripts.length) { console.error("GATE ERROR: no <script> block in " + f + " - gate would be vacuous"); process.exit(2); }

  scripts.forEach((s, i) => {
    blocks++;
    try {
      new Function(s[1]);                       // parse only; never executed
      console.log("  ok      " + path.basename(f) + " script #" + (i + 1) + " (" + s[1].length + " chars)");
    } catch (e) {
      fail++;
      // locate the offending line for the report
      const probe = s[1].split("\n");
      let line = "?";
      for (let n = 1; n <= probe.length; n++) {
        try { new Function(probe.slice(0, n).join("\n")); line = "?"; }
        catch (_) { line = String(n); break; }
      }
      console.error("  PARSE FAIL  " + path.basename(f) + " script #" + (i + 1) + ": " + e.message + " (near line " + line + " of the block)");
    }
  });
}
if (fail) { console.error("\nA page whose script cannot parse ships a DEAD app. Nothing was committed."); process.exit(1); }
console.log("PAGE-PARSE PASS - " + blocks + " script block(s)");
