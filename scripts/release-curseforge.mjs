#!/usr/bin/env node
/**
 * Cross-shell (PowerShell + Git Bash) local CurseForge release script for RetPulse.
 *
 * Usage:
 *   node scripts/release-curseforge.mjs [--dry-run] [--skip-tests] [--release-type release|beta|alpha] [--changelog "..."]
 *
 * Reads CF_API_KEY from environment or gitignored `.env.local` in the repo root.
 */

import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, "..");
const ADDON_NAME = "RetPulse";
const ADDON_DIR = path.join(REPO_ROOT, ADDON_NAME);
const TOC_PATH = path.join(ADDON_DIR, `${ADDON_NAME}.toc`);
const DIST_DIR = path.join(REPO_ROOT, "dist");

function parseArgs(argv) {
	const opts = {
		dryRun: false,
		skipTests: false,
		releaseType: "release",
		changelog: null,
	};
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === "--dry-run") opts.dryRun = true;
		else if (a === "--skip-tests") opts.skipTests = true;
		else if (a === "--release-type" && argv[i + 1]) opts.releaseType = argv[++i];
		else if (a === "--changelog" && argv[i + 1]) opts.changelog = argv[++i];
		else if (a === "-h" || a === "--help") {
			console.log(
				"Usage: node scripts/release-curseforge.mjs [--dry-run] [--skip-tests] [--release-type release|beta|alpha] [--changelog \"...\"]"
			);
			process.exit(0);
		}
	}
	return opts;
}

function loadApiKey() {
	if (process.env.CF_API_KEY && process.env.CF_API_KEY.trim()) {
		return process.env.CF_API_KEY.trim();
	}
	const envFile = path.join(REPO_ROOT, ".env.local");
	if (fs.existsSync(envFile)) {
		for (const rawLine of fs.readFileSync(envFile, "utf8").split(/\r?\n/)) {
			const line = rawLine.trim();
			if (!line || line.startsWith("#")) continue;
			const eq = line.indexOf("=");
			if (eq === -1) continue;
			const key = line.slice(0, eq).trim();
			let val = line.slice(eq + 1).trim();
			if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
				val = val.slice(1, -1);
			}
			if (key === "CF_API_KEY" && val) return val;
		}
	}
	throw new Error(
		"Missing CF_API_KEY. Set CF_API_KEY in your environment or add CF_API_KEY=<token> to .env.local (gitignored)."
	);
}

function parseToc(tocPath) {
	const text = fs.readFileSync(tocPath, "utf8");
	const meta = {};
	const files = [];
	for (const rawLine of text.split(/\r?\n/)) {
		const line = rawLine.trim();
		if (!line) continue;
		if (line.startsWith("##")) {
			const m = line.match(/^##\s*([^:]+):\s*(.+)$/);
			if (m) meta[m[1].trim()] = m[2].trim();
		} else if (!line.startsWith("#")) {
			files.push(line.replace(/\\/g, "/"));
		}
	}
	if (!meta.Version) throw new Error("Missing ## Version in RetPulse.toc");
	if (!meta["X-Curse-Project-ID"]) throw new Error("Missing ## X-Curse-Project-ID in RetPulse.toc");
	if (!meta.Interface) throw new Error("Missing ## Interface in RetPulse.toc");
	return { meta, files };
}

function interfaceToVersionString(iface) {
	const n = Number(String(iface).split(",")[0].trim());
	if (!Number.isFinite(n) || n < 10000) {
		throw new Error(`Invalid ## Interface value: ${iface}`);
	}
	const major = Math.floor(n / 10000);
	const minor = Math.floor((n % 10000) / 100);
	const patch = n % 100;
	return `${major}.${minor}.${patch}`;
}

function runTests() {
	console.log("==> Running RetPulse unit tests...");
	const isWin = process.platform === "win32";
	const res = isWin
		? spawnSync("cmd.exe", ["/d", "/s", "/c", "npx --yes --package=fengari-node-cli fengari tests/run_tests.lua"], {
				cwd: ADDON_DIR,
				stdio: "inherit",
			})
		: spawnSync("npx", ["--yes", "--package=fengari-node-cli", "fengari", "tests/run_tests.lua"], {
				cwd: ADDON_DIR,
				stdio: "inherit",
			});
	if (res.status !== 0) {
		throw new Error(`Unit tests failed with exit code ${res.status}`);
	}
}

function getChangelogFromFile(version) {
	const candidates = [
		path.join(ADDON_DIR, "CHANGELOG.md"),
		path.join(REPO_ROOT, "CHANGELOG.md"),
	];
	const changelogPath = candidates.find((p) => fs.existsSync(p));
	if (!changelogPath) return null;

	const text = fs.readFileSync(changelogPath, "utf8").replace(/\r\n/g, "\n");
	const escaped = version.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
	const headerRe = new RegExp(`^##\\s+\\[?v?${escaped}\\]?(?:\\s|$).*$`, "m");
	const match = headerRe.exec(text);
	if (!match) return null;

	const start = match.index + match[0].length;
	const rest = text.slice(start);
	const nextHeading = rest.search(/\n##\s+/);
	const body = (nextHeading === -1 ? rest : rest.slice(0, nextHeading)).trim();
	if (!body) return null;

	return `### ${ADDON_NAME} v${version}\n\n${body}`;
}

function getAutoChangelog(version) {
	try {
		const tags = execFileSync("git", ["tag", "--sort=-v:refname"], {
			cwd: REPO_ROOT,
			encoding: "utf8",
		})
			.split(/\r?\n/)
			.map((s) => s.trim())
			.filter(Boolean);

		const currentTag = `v${version}`;
		const prevTag = tags.find((t) => t !== currentTag);
		const range = prevTag ? `${prevTag}..HEAD` : "HEAD~5..HEAD";
		const log = execFileSync("git", ["log", range, "--pretty=format:- %s", "--", ADDON_NAME], {
			cwd: REPO_ROOT,
			encoding: "utf8",
		}).trim();
		if (log) {
			return `### RetPulse v${version}\n\n${log}`;
		}
	} catch {
		// Fall back to a simple note if git history isn't available.
	}
	return `### RetPulse v${version}\n\nRelease v${version}.`;
}

async function resolveGameVersionId(apiKey, versionStr) {
	const resp = await fetch("https://wow.curseforge.com/api/game/versions", {
		headers: { "X-Api-Token": apiKey },
	});
	if (!resp.ok) {
		throw new Error(`Failed to fetch CurseForge game versions: HTTP ${resp.status} ${await resp.text()}`);
	}
	const versions = await resp.json();
	const exact = versions.find((v) => v.name === versionStr);
	if (exact) return exact;
	throw new Error(
		`Could not find WoW game version "${versionStr}" in CurseForge API. Available 1.60.x: ${versions
			.filter((v) => String(v.name).startsWith("1.60"))
			.map((v) => `${v.name} (id=${v.id})`)
			.join(", ")}`
	);
}

function buildZip(version, tocFiles) {
	fs.mkdirSync(DIST_DIR, { recursive: true });
	const stageRoot = path.join(DIST_DIR, `_stage_${version}`);
	const stageAddon = path.join(stageRoot, ADDON_NAME);
	fs.rmSync(stageRoot, { recursive: true, force: true });
	fs.mkdirSync(stageAddon, { recursive: true });

	const filesToCopy = [`${ADDON_NAME}.toc`, ...tocFiles];
	if (fs.existsSync(path.join(ADDON_DIR, "CHANGELOG.md"))) filesToCopy.push("CHANGELOG.md");
	if (fs.existsSync(path.join(ADDON_DIR, "LICENSE"))) filesToCopy.push("LICENSE");
	if (fs.existsSync(path.join(REPO_ROOT, "LICENSE")) && !filesToCopy.includes("LICENSE")) {
		fs.copyFileSync(path.join(REPO_ROOT, "LICENSE"), path.join(stageAddon, "LICENSE"));
	}

	for (const rel of filesToCopy) {
		const src = path.join(ADDON_DIR, rel);
		const dst = path.join(stageAddon, rel);
		if (!fs.existsSync(src)) {
			throw new Error(`TOC references missing file: ${rel}`);
		}
		fs.mkdirSync(path.dirname(dst), { recursive: true });
		fs.copyFileSync(src, dst);
	}

	const zipPath = path.join(DIST_DIR, `${ADDON_NAME}-${version}.zip`);
	fs.rmSync(zipPath, { force: true });

	// Use Windows System32 bsdtar on win32 so Git Bash's GNU tar (which misparses
	// drive letters like E:\ as remote hosts) is never picked up from PATH.
	const tarBin =
		process.platform === "win32"
			? path.join(process.env.SystemRoot || "C:\\Windows", "System32", "tar.exe")
			: "tar";
	execFileSync(tarBin, ["-a", "-cf", zipPath, "-C", stageRoot, ADDON_NAME], {
		stdio: "inherit",
	});

	fs.rmSync(stageRoot, { recursive: true, force: true });
	return zipPath;
}

async function uploadToCurseForge(apiKey, projectId, zipPath, metadata) {
	const form = new FormData();
	form.append("metadata", JSON.stringify(metadata));
	const zipBytes = fs.readFileSync(zipPath);
	form.append("file", new Blob([zipBytes], { type: "application/zip" }), path.basename(zipPath));

	const url = `https://wow.curseforge.com/api/projects/${projectId}/upload-file`;
	const resp = await fetch(url, {
		method: "POST",
		headers: { "X-Api-Token": apiKey },
		body: form,
	});
	const bodyText = await resp.text();
	if (!resp.ok) {
		throw new Error(`CurseForge upload failed: HTTP ${resp.status} ${bodyText}`);
	}
	return JSON.parse(bodyText);
}

async function main() {
	const opts = parseArgs(process.argv.slice(2));
	const { meta, files } = parseToc(TOC_PATH);
	const version = meta.Version;
	const projectId = meta["X-Curse-Project-ID"];
	const gameVersionStr = interfaceToVersionString(meta.Interface);

	console.log(`==> ${ADDON_NAME} v${version} | CurseForge Project ${projectId} | WoW ${gameVersionStr}`);

	if (!opts.skipTests) {
		runTests();
	}

	const apiKey = loadApiKey();
	console.log(`==> Resolving CurseForge game version for ${gameVersionStr}...`);
	const gameVersion = await resolveGameVersionId(apiKey, gameVersionStr);
	console.log(`    Matched: ${gameVersion.name} (id=${gameVersion.id})`);

	console.log("==> Building clean release ZIP...");
	const zipPath = buildZip(version, files);
	const sizeKb = (fs.statSync(zipPath).size / 1024).toFixed(1);
	console.log(`    Created: ${zipPath} (${sizeKb} KB)`);

	const changelog = opts.changelog || getChangelogFromFile(version) || getAutoChangelog(version);
	const metadata = {
		changelog,
		changelogType: "markdown",
		displayName: `${ADDON_NAME} v${version}`,
		gameVersions: [gameVersion.id],
		releaseType: opts.releaseType,
	};

	if (opts.dryRun) {
		console.log("\n[DRY RUN] Would upload with metadata:");
		console.log(JSON.stringify(metadata, null, 2));
		return;
	}

	console.log("==> Uploading to CurseForge...");
	const result = await uploadToCurseForge(apiKey, projectId, zipPath, metadata);
	console.log(`==> Upload succeeded! CurseForge File ID: ${result.id}`);
	console.log(`    https://authors.curseforge.com/#/projects/${projectId}/files`);
}

main().catch((err) => {
	console.error(`\n[ERROR] ${err.message}`);
	process.exit(1);
});
