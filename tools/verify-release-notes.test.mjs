import { readFile } from "node:fs/promises";
import { argv, cwd, exit } from "node:process";

const CONFIG_PATH = ".releaserc.json";
const PLUGIN_NAME = "@semantic-release/release-notes-generator";
const REPOSITORY_URL = "https://github.com/gufranco/synology-downloadstation-bt-fix";

const SAMPLE_COMMITS = [
  {
    hash: "0000000000000000000000000000000000000001",
    message: "feat(scripts): register the boot task with one command\n\nBody text.",
    subject: "register the boot task with one command",
    committerDate: "2026-01-01",
  },
  {
    hash: "0000000000000000000000000000000000000002",
    message: "fix(patches): keep the task id across a daemon restart",
    subject: "keep the task id across a daemon restart",
    committerDate: "2026-01-02",
  },
  {
    hash: "0000000000000000000000000000000000000003",
    message: "docs(readme): describe the duplicate-add test",
    subject: "describe the duplicate-add test",
    committerDate: "2026-01-03",
  },
  {
    hash: "0000000000000000000000000000000000000004",
    message: "build(deps): bump the pinned upstream tarball\n\nBREAKING CHANGE: drops the 4.0.x fallback.",
    subject: "bump the pinned upstream tarball",
    committerDate: "2026-01-04",
  },
];

const MUST_RENDER = [
  "register the boot task with one command",
  "keep the task id across a daemon restart",
  "describe the duplicate-add test",
  "drops the 4.0.x fallback",
];

async function readPluginConfig() {
  const raw = JSON.parse(await readFile(CONFIG_PATH, "utf8"));
  const entry = (raw.plugins ?? []).find(
    (plugin) => plugin === PLUGIN_NAME || (Array.isArray(plugin) && plugin[0] === PLUGIN_NAME),
  );
  if (!entry) {
    throw new Error(`${PLUGIN_NAME} is not configured in ${CONFIG_PATH}`);
  }
  return Array.isArray(entry) ? (entry[1] ?? {}) : {};
}

function buildContext() {
  return {
    cwd: cwd(),
    options: { repositoryUrl: REPOSITORY_URL },
    lastRelease: { gitTag: "v2.0.0", version: "2.0.0" },
    nextRelease: { gitTag: "v2.1.0", version: "2.1.0", type: "minor" },
    commits: SAMPLE_COMMITS,
    logger: { log: () => {}, error: () => {} },
  };
}

function assertRendered(notes) {
  if (typeof notes !== "string" || notes.trim() === "") {
    throw new Error("the generator produced empty release notes");
  }
  const missing = MUST_RENDER.filter((text) => !notes.includes(text));
  if (missing.length > 0) {
    throw new Error(`rendered notes omitted expected commits: ${missing.join(", ")}`);
  }
}

async function main() {
  const pluginConfig = await readPluginConfig();
  const { generateNotes } = await import(PLUGIN_NAME);
  const notes = await generateNotes(pluginConfig, buildContext());
  assertRendered(notes);
  if (argv.includes("--print")) {
    console.log(notes);
  }
  console.log(`release notes render with preset "${pluginConfig.preset ?? "angular"}"`);
}

main().catch((error) => {
  console.error(`verify-release-notes failed: ${error.message}`);
  exit(1);
});
