#!/usr/bin/env node
// Consult the sibling reference implementation BEFORE designing a subsystem it already
// solved, on a device, in production.
//
// WHY THIS EXISTS: three subsystems here were designed from scratch when TomeRoam --
// a working, device-proven sibling project sitting on the same disk -- had already
// solved them, and in each case its answer was better:
//   * the APK self-updater  (I had a toast with no route to act on it)
//   * page-to-shell calls   (I used a URL scheme; its bridge + feature detection wins)
//   * the update re-check   (I used a native timer; its visibilitychange in the WEB
//                            layer needs no APK and works on any shell)
// The user had to ask "what does TomeRoam do?" all three times. Asking must be cheaper
// than guessing, so this makes it one command -- and the commit-msg hook makes citing
// the answer mandatory for changes in these areas.
//
// Usage:
//   node tools/reference-check.mjs update      topic alias
//   node tools/reference-check.mjs bridge
//   node tools/reference-check.mjs "some regex"
//   node tools/reference-check.mjs --topics
// Exit 0 with hits, 1 with none, 2 if the reference tree is missing.

import fs from "node:fs";
import path from "node:path";

const REF = "C:/Users/nzilb/OneDrive/Desktop/TomeRoam";

// Curated entry points: subsystem -> what to grep, and where the answer lives.
const TOPICS = {
  update: { re: "checkAsync|nativeVersion|minNativeVersion|staged|promoteStaged|reg\\.update",
            note: "Native check runs ONCE at onCreate. The RE-CHECK is web-side: visibilitychange -> reg.update(). Staged builds apply on an explicit tap, never mid-session." },
  apk:    { re: "ApkUpdater|REQUEST_INSTALL_PACKAGES|package-archive|canRequestPackageInstalls",
            note: "Soft prompt when a newer shell exists; hard re-prompt each launch when a web build REQUIRES it; in-app download handed to the system installer via a tiny ContentProvider." },
  bridge: { re: "addJavascriptInterface|JavascriptInterface|TomeRoamNative",
            note: "A deliberately tiny bridge, FEATURE-DETECTED by the page. No version arithmetic in the page; no URL schemes." },
  webview:{ re: "WebSettings|setUseWideViewPort|setMixedContentMode|WebViewAssetLoader|loadUrl",
            note: "Check viewport/mixed-content settings here before debugging layout differences." },
  insets: { re: "WindowInsets|setOnApplyWindowInsets|systemBars|FrameLayout",
            note: "Pad the CONTAINER, never the WebView: it anchors position:fixed to its full box and ignores its own padding." },
  build:  { re: "versionCode|versionName|NATIVE_VERSION|aapt2|apksigner|keystore",
            note: "Dependency-free build: aapt2/javac/d8/jar/zipalign/apksigner. Assets via jar, not aapt2 -A." },
  sw:     { re: "serviceWorker|skipWaiting|userApply|waiting|controllerchange",
            note: "Updates apply only on an explicit user action -- it has a surprise-auto-update bug history." },
};

const arg = process.argv[2];
if (!arg || arg === "--topics") {
  console.log("topics: " + Object.keys(TOPICS).join(", "));
  console.log("or pass any regex. Reference tree: " + REF);
  process.exit(arg ? 0 : 2);
}
if (!fs.existsSync(REF)) { console.error("reference tree not found: " + REF); process.exit(2); }

const topic = TOPICS[arg];
const re = new RegExp(topic ? topic.re : arg, "i");

const SKIP = new Set(["node_modules", ".git", "build", "Claude", ".claude"]);
const EXT = new Set([".java", ".js", ".mjs", ".html", ".json", ".xml", ".ps1", ".sh", ".md"]);
const hits = [];
(function walk(dir) {
  let ents;
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of ents) {
    if (SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { walk(p); continue; }
    if (!EXT.has(path.extname(e.name))) continue;
    let body;
    try { body = fs.readFileSync(p, "utf8"); } catch { continue; }
    body.split(/\r?\n/).forEach((line, i) => {
      if (re.test(line)) hits.push({ f: path.relative(REF, p).split(path.sep).join("/"), n: i + 1, line: line.trim().slice(0, 150) });
    });
  }
})(REF);

if (topic) console.log("WHAT THE REFERENCE DOES: " + topic.note + "\n");
if (!hits.length) { console.log("no hits for /" + re.source + "/ in " + REF); process.exit(1); }

// group by file so the shape of the answer is visible, not just a line dump
const byFile = {};
for (const h of hits) (byFile[h.f] ??= []).push(h);
const files = Object.entries(byFile).sort((a, b) => b[1].length - a[1].length);
console.log(hits.length + " hit(s) in " + files.length + " file(s):\n");
for (const [f, hs] of files.slice(0, 8)) {
  console.log("  " + f + "  (" + hs.length + ")");
  for (const h of hs.slice(0, 4)) console.log("      " + h.n + ": " + h.line);
  if (hs.length > 4) console.log("      … " + (hs.length - 4) + " more");
}
if (files.length > 8) console.log("  … " + (files.length - 8) + " more file(s)");
