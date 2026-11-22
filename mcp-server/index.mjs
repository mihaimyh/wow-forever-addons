import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const WOW_ROOT = process.env.WOW_FOREVER_ROOT || "E:\\Games\\World of Warcraft\\_forever_";
const ADDONS_DIR = path.join(WOW_ROOT, "Interface", "AddOns");
const WTF_ACCOUNTS_DIR = path.join(WOW_ROOT, "WTF", "Account");
const LOGS_DIR = path.join(WOW_ROOT, "Logs");
const BLIZZ_CODE_DIR = path.join(WOW_ROOT, "BlizzardInterfaceCode");

function exists(p) {
  try {
    fs.accessSync(p);
    return true;
  } catch {
    return false;
  }
}

function safeResolve(baseDir, relPath) {
  const resolved = path.resolve(baseDir, relPath);
  const base = path.resolve(baseDir);
  if (!resolved.startsWith(base + path.sep) && resolved !== base) {
    throw new Error("Path escapes allowed directory");
  }
  return resolved;
}

function listAccounts() {
  if (!exists(WTF_ACCOUNTS_DIR)) return [];
  return fs
    .readdirSync(WTF_ACCOUNTS_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory() && d.name !== "SavedVariables")
    .map((d) => d.name);
}

function findSavedVarFiles(addonName) {
  const results = [];
  for (const acc of listAccounts()) {
    const file = path.join(WTF_ACCOUNTS_DIR, acc, "SavedVariables", `${addonName}.lua`);
    if (exists(file)) {
      const stat = fs.statSync(file);
      results.push({ account: acc, file, mtime: stat.mtime.toISOString(), size: stat.size });
    }
  }
  results.sort((a, b) => (a.mtime < b.mtime ? 1 : -1));
  return results;
}

function parseSavedVarsSummary(content) {
  const lines = content.split(/\r?\n/);
  const summary = {};
  const arrays = {};
  let currentArray = null;

  for (const line of lines) {
    const scalar = line.match(/^\["([^"]+)"\]\s*=\s*(.+?),?\s*$/);
    if (scalar) {
      const [, key, rawVal] = scalar;
      if (rawVal === "{") {
        currentArray = key;
        arrays[key] = [];
      } else {
        currentArray = null;
        summary[key] = rawVal.replace(/^"(.*)"$/, "$1");
      }
      continue;
    }
    if (currentArray) {
      if (line.trim() === "},") {
        currentArray = null;
      } else {
        const entry = line.trim().replace(/^"(.*)",?$/, "$1");
        if (entry) arrays[currentArray].push(entry);
      }
    }
  }
  return { summary, arrays };
}

function walkFiles(dir, exts, limit = 5000, out = []) {
  if (!exists(dir) || out.length >= limit) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (out.length >= limit) break;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkFiles(full, exts, limit, out);
    } else if (!exts || exts.some((e) => entry.name.toLowerCase().endsWith(e))) {
      out.push(full);
    }
  }
  return out;
}

const server = new McpServer({
  name: "wow-forever-mcp",
  version: "1.0.0",
});

// 1. client_status
server.tool(
  "client_status",
  "Inspect the local WoW: Forever (_forever_) directory, WTF accounts, exported BlizzardInterfaceCode status, Logs, and installed addons.",
  {},
  async () => {
    const accounts = listAccounts();
    const addons = exists(ADDONS_DIR)
      ? fs.readdirSync(ADDONS_DIR, { withFileTypes: true }).filter((d) => d.isDirectory() || d.isSymbolicLink()).map((d) => d.name)
      : [];
    const logs = exists(LOGS_DIR)
      ? fs.readdirSync(LOGS_DIR).map((name) => {
          const st = fs.statSync(path.join(LOGS_DIR, name));
          return { name, size: st.size, mtime: st.mtime.toISOString() };
        })
      : [];
    const blizzExported = exists(BLIZZ_CODE_DIR);
    const blizzLuaCount = blizzExported ? walkFiles(BLIZZ_CODE_DIR, [".lua"], 5000).length : 0;

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              wowRoot: WOW_ROOT,
              accounts,
              blizzardInterfaceCodeExported: blizzExported,
              blizzardLuaFiles: blizzLuaCount,
              exportHint: blizzExported
                ? null
                : "To enable search_wow_api & read_framexml, launch Wow.exe with -console and run: ExportInterfaceFiles code",
              logs,
              addonCount: addons.length,
              addons,
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// 2. read_saved_vars
server.tool(
  "read_saved_vars",
  "Read SavedVariables (<addonName>.lua) from WoW: Forever WTF folder. Returns scalar fields and optionally the tail of an array section (e.g. debugLog, combatLog, traceLog, dump).",
  {
    addonName: z.string().describe("Addon SavedVariables base name, e.g. RetPulse"),
    section: z.string().optional().describe("Optional array key to return, e.g. debugLog, combatLog, traceLog, dump"),
    tailLines: z.number().int().min(1).max(500).optional().default(80).describe("Number of trailing lines to return for section"),
  },
  async ({ addonName, section, tailLines }) => {
    const matches = findSavedVarFiles(addonName);
    if (matches.length === 0) {
      return {
        content: [{ type: "text", text: `No SavedVariables found for '${addonName}' under ${WTF_ACCOUNTS_DIR}.` }],
      };
    }
    const target = matches[0];
    const content = fs.readFileSync(target.file, "utf8");
    const { summary, arrays } = parseSavedVarsSummary(content);

    const payload = {
      file: target.file,
      account: target.account,
      mtime: target.mtime,
      size: target.size,
      summary,
      arraySections: Object.fromEntries(Object.entries(arrays).map(([k, v]) => [k, v.length])),
    };
    if (section) {
      const list = arrays[section] || [];
      payload.section = section;
      payload.lines = list.slice(-tailLines);
    }
    return { content: [{ type: "text", text: JSON.stringify(payload, null, 2) }] };
  }
);

// 3. read_lua_errors
server.tool(
  "read_lua_errors",
  "Read recent Lua errors from BugGrabber SavedVariables (if installed), RetPulse lastError, and WoW Logs (taint.log, FrameXML.log).",
  {
    maxLines: z.number().int().min(10).max(300).optional().default(60),
  },
  async ({ maxLines }) => {
    const report = { bugGrabber: null, retPulseLastError: null, logs: {} };

    const bg = findSavedVarFiles("!BugGrabber")[0] || findSavedVarFiles("BugGrabber")[0];
    if (bg) {
      const raw = fs.readFileSync(bg.file, "utf8");
      report.bugGrabber = {
        file: bg.file,
        mtime: bg.mtime,
        tail: raw.split(/\r?\n/).slice(-maxLines).join("\n"),
      };
    }

    const rp = findSavedVarFiles("RetPulse")[0];
    if (rp) {
      const { summary } = parseSavedVarsSummary(fs.readFileSync(rp.file, "utf8"));
      report.retPulseLastError = summary.lastError || "none";
    }

    for (const logName of ["taint.log", "FrameXML.log"]) {
      const logPath = path.join(LOGS_DIR, logName);
      if (exists(logPath)) {
        const lines = fs.readFileSync(logPath, "utf8").split(/\r?\n/);
        report.logs[logName] = lines.slice(-maxLines);
      }
    }

    return { content: [{ type: "text", text: JSON.stringify(report, null, 2) }] };
  }
);

// 4. search_wow_api
server.tool(
  "search_wow_api",
  "Search exported BlizzardInterfaceCode (Blizzard_APIDocumentationGenerated & FrameXML) for WoW: Forever 16001 APIs, events, and Secret annotations.",
  {
    query: z.string().min(2).describe("Symbol, API name, or event to search (case-insensitive)"),
    limit: z.number().int().min(1).max(100).optional().default(30),
  },
  async ({ query, limit }) => {
    if (!exists(BLIZZ_CODE_DIR)) {
      return {
        content: [
          {
            type: "text",
            text:
              `BlizzardInterfaceCode is not exported yet at ${BLIZZ_CODE_DIR}.\n` +
              `To export the exact 16001 API docs & FrameXML from your client:\n` +
              `1. Launch Wow.exe with -console (or add -console in Battle.net Additional Command Line Arguments)\n` +
              `2. Press ~ on the login/character screen and run: ExportInterfaceFiles code`,
          },
        ],
      };
    }

    const docDir = path.join(BLIZZ_CODE_DIR, "Interface", "AddOns", "Blizzard_APIDocumentationGenerated");
    const searchRoot = exists(docDir) ? docDir : BLIZZ_CODE_DIR;
    const files = walkFiles(searchRoot, [".lua"], 4000);
    const needle = query.toLowerCase();
    const hits = [];

    for (const file of files) {
      if (hits.length >= limit) break;
      const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().includes(needle)) {
          hits.push({
            file: path.relative(BLIZZ_CODE_DIR, file),
            line: i + 1,
            text: lines[i].trim().slice(0, 200),
          });
          if (hits.length >= limit) break;
        }
      }
    }

    return { content: [{ type: "text", text: JSON.stringify({ query, count: hits.length, hits }, null, 2) }] };
  }
);

// 5. read_framexml
server.tool(
  "read_framexml",
  "Read lines from an exported BlizzardInterfaceCode file (relative path from BlizzardInterfaceCode/).",
  {
    relativePath: z.string().describe("Relative path inside BlizzardInterfaceCode/"),
    startLine: z.number().int().min(1).optional().default(1),
    endLine: z.number().int().min(1).optional().default(120),
  },
  async ({ relativePath, startLine, endLine }) => {
    if (!exists(BLIZZ_CODE_DIR)) {
      return { content: [{ type: "text", text: "BlizzardInterfaceCode is not exported yet." }] };
    }
    const full = safeResolve(BLIZZ_CODE_DIR, relativePath);
    if (!exists(full)) {
      return { content: [{ type: "text", text: `File not found: ${relativePath}` }] };
    }
    const lines = fs.readFileSync(full, "utf8").split(/\r?\n/);
    const slice = lines.slice(startLine - 1, Math.min(endLine, startLine + 250));
    const numbered = slice.map((l, idx) => `${startLine + idx}: ${l}`).join("\n");
    return { content: [{ type: "text", text: numbered }] };
  }
);

// 6. validate_addon
server.tool(
  "validate_addon",
  "Validate a WoW: Forever (16001) addon: check TOC interface version & file list, scan for blocked/legacy APIs, and run offline Lua tests if tests/run_tests.lua exists.",
  {
    addonName: z.string().describe("Addon folder name inside Interface/AddOns, e.g. RetPulse or ChatCopy"),
  },
  async ({ addonName }) => {
    const addonDir = safeResolve(ADDONS_DIR, addonName);
    if (!exists(addonDir)) {
      return { content: [{ type: "text", text: `Addon folder not found: ${addonDir}` }] };
    }

    const issues = [];
    const tocPath = path.join(addonDir, `${addonName}.toc`);
    const listedFiles = [];
    if (!exists(tocPath)) {
      issues.push({ severity: "error", file: `${addonName}.toc`, message: "Missing TOC file" });
    } else {
      const tocLines = fs.readFileSync(tocPath, "utf8").split(/\r?\n/);
      const has16001 = tocLines.some((l) => /^##\s*Interface:\s*.*16001/.test(l));
      if (!has16001) {
        issues.push({ severity: "warn", file: `${addonName}.toc`, message: "TOC does not declare Interface: 16001" });
      }
      for (const raw of tocLines) {
        const line = raw.trim();
        if (!line || line.startsWith("#")) continue;
        listedFiles.push(line);
        if (!exists(path.join(addonDir, line))) {
          issues.push({ severity: "error", file: `${addonName}.toc`, message: `Listed file missing: ${line}` });
        }
      }
    }

    const forbiddenPatterns = [
      { re: /COMBAT_LOG_EVENT_UNFILTERED/, msg: "COMBAT_LOG_EVENT_UNFILTERED is blocked on WoW: Forever" },
      { re: /(?<![.\w])GetSpellInfo\s*\(/, msg: "Legacy global GetSpellInfo(); use C_Spell.GetSpellInfo()" },
      { re: /(?<![.\w])GetContainerItemInfo\s*\(/, msg: "Legacy global GetContainerItemInfo(); use C_Container.GetContainerItemInfo()" },
      { re: /(?<![.\w])InterfaceOptions_AddCategory\s*\(/, msg: "Legacy InterfaceOptions_AddCategory(); use Settings API" },
      { re: /(?<![.\w])PlaySoundFile\s*\([^)]*\.ogg/i, msg: "PlaySoundFile on .ogg paths is unreliable on Forever; use PlaySound(SOUNDKIT.*)" },
    ];

    const luaFiles = walkFiles(addonDir, [".lua"], 500).filter((f) => !f.includes(`${path.sep}tests${path.sep}`));
    for (const file of luaFiles) {
      const rel = path.relative(addonDir, file);
      const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
      lines.forEach((line, i) => {
        if (line.trim().startsWith("--")) return;
        for (const rule of forbiddenPatterns) {
          if (rule.re.test(line)) {
            issues.push({ severity: "error", file: rel, line: i + 1, message: rule.msg });
          }
        }
      });
    }

    let testOutput = null;
    const testScript = path.join(addonDir, "tests", "run_tests.lua");
    if (exists(testScript)) {
      try {
        const out = execFileSync(
          "npx",
          ["--yes", "--package=fengari-node-cli", "fengari", "tests/run_tests.lua"],
          { cwd: addonDir, encoding: "utf8", timeout: 20000, shell: process.platform === "win32" }
        );
        testOutput = { ok: true, output: out.trim() };
      } catch (err) {
        testOutput = { ok: false, output: (err.stdout || err.message || "").toString().trim() };
      }
    }

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              addon: addonName,
              addonDir,
              tocFiles: listedFiles,
              luaFilesChecked: luaFiles.length,
              issues,
              tests: testOutput,
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// 7. capture_wow_screenshot
server.tool(
  "capture_wow_screenshot",
  "Capture a read-only Windows desktop screenshot of the World of Warcraft game window to a PNG file for visual addon debugging.",
  {
    outputPath: z.string().optional().describe("Optional absolute PNG path; defaults to temp folder"),
  },
  async ({ outputPath }) => {
    if (process.platform !== "win32") {
      return { content: [{ type: "text", text: "capture_wow_screenshot is only supported on Windows." }] };
    }
    const targetPath = outputPath || path.join(os.tmpdir(), "wow-forever-mcp-screenshot.png");
    const psScript = `
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinRectHelper {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
"@
$hwnd = [WinRectHelper]::FindWindow("GxWindowClass", $null)
if ($hwnd -eq [IntPtr]::Zero) { $hwnd = [WinRectHelper]::FindWindow($null, "World of Warcraft") }
if ($hwnd -eq [IntPtr]::Zero) {
  $proc = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and ($_.ProcessName -match '^Wow' -or $_.MainWindowTitle -like '*World of Warcraft*') } | Select-Object -First 1
  if ($proc) { $hwnd = $proc.MainWindowHandle }
}
$mode = "window"
$left = 0; $top = 0; $w = 0; $h = 0
if ($hwnd -ne [IntPtr]::Zero) {
  $rect = New-Object WinRectHelper+RECT
  [WinRectHelper]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
  $left = $rect.Left; $top = $rect.Top
  $w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
}
if ($w -lt 100 -or $h -lt 100) {
  $mode = "primary_screen"
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $left = $bounds.X; $top = $bounds.Y; $w = $bounds.Width; $h = $bounds.Height
}
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($left, $top, 0, 0, $bmp.Size)
$outPath = '${targetPath.replace(/'/g, "''")}'
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()
[PSCustomObject]@{ path = $outPath; width = $w; height = $h; mode = $mode } | ConvertTo-Json -Compress
`;
    try {
      const stdout = execFileSync("powershell.exe", ["-NoProfile", "-Command", psScript], {
        encoding: "utf8",
        timeout: 15000,
      }).trim();
      return { content: [{ type: "text", text: stdout }] };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Screenshot failed: ${(err.stderr || err.message || "").toString().trim()}` }],
      };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
