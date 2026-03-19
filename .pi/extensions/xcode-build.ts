/**
 * Xcode CLI Extension for pi
 *
 * Registers xcode_build and xcode_run tools via xcode-cli.
 * Shows ⏳ status with project name, config, git commit, and dirty state during operations.
 * Persists ✓/✗ status with error/warning counts after completion.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { truncateTail, DEFAULT_MAX_BYTES, DEFAULT_MAX_LINES, formatSize } from "@mariozechner/pi-coding-agent";
import { Text } from "@mariozechner/pi-tui";
import { Type } from "@sinclair/typebox";
import { spawn } from "child_process";

function addProjectArgs(args: string[], params: any) {
  if (params.workspace) args.push("--workspace", params.workspace);
  if (params.project) args.push("--project", params.project);
  if (params.scheme) args.push("-s", params.scheme);
}

function formatIssues(errorCount: number, warningCount: number): string {
  const parts: string[] = [];
  if (errorCount > 0) parts.push(`${errorCount} error${errorCount > 1 ? "s" : ""}`);
  if (warningCount > 0) parts.push(`${warningCount} warning${warningCount > 1 ? "s" : ""}`);
  return parts.length ? ` | ${parts.join(", ")}` : "";
}

function truncateOutput(output: string): string {
  const truncation = truncateTail(output, { maxLines: DEFAULT_MAX_LINES, maxBytes: DEFAULT_MAX_BYTES });
  let result = truncation.content;
  if (truncation.truncated) {
    result += `\n\n[Output truncated: ${truncation.outputLines} of ${truncation.totalLines} lines`;
    result += ` (${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)})]`;
  }
  return result;
}

async function resolveInfo(pi: ExtensionAPI, params: any, signal: AbortSignal | undefined) {
  const infoArgs: string[] = ["info"];
  addProjectArgs(infoArgs, params);

  let label = params.scheme ?? "project";
  let destination = params.destination ?? "";
  let commit = "";
  let uncommitted = 0;

  const result = await pi.exec("xcode-cli", infoArgs, { signal, timeout: 15_000 });
  if (result.code === 0) {
    try {
      const info = JSON.parse(result.stdout);
      label = info.label ?? label;
      destination = destination || info.destination || "";
      commit = info.commit ?? "";
      uncommitted = info.uncommitted ?? 0;
    } catch {}
  }
  return { label, destination, commit, uncommitted };
}

function buildStatusBase(label: string, config: string, destination: string, commit: string, uncommitted: number) {
  const destPart = destination ? ` | ${destination}` : "";
  const gitPart = commit ? ` | ${commit}` : "";
  const dirtyPart = commit ? (uncommitted > 0 ? ` | ${uncommitted} uncommitted` : " | clean") : "";
  return `${label} | ${config}${destPart}${gitPart}${dirtyPart}`;
}

export default function (pi: ExtensionAPI) {
  let appMonitor: ReturnType<typeof setInterval> | null = null;
  let consolePid: number | null = null;
  let currentLogFile: string | null = null;
  let currentBundleId: string | null = null;
  const LOG_FILE_PREFIX = "/tmp/xcode-cli-console-";

  function stopMonitor() {
    if (appMonitor) { clearInterval(appMonitor); appMonitor = null; }
  }

  function stopConsole() {
    if (consolePid) {
      try { process.kill(consolePid, "SIGTERM"); } catch {}
      consolePid = null;
    }
  }

  async function stopDebug() {
    await pi.exec("xcode-cli", ["debug", "stop"], { timeout: 5_000 }).catch(() => {});
  }

  pi.on("session_shutdown", async () => { stopMonitor(); stopConsole(); await stopDebug(); });
  // ── xcode_build ──────────────────────────────────────────────────────

  pi.registerTool({
    name: "xcode_build",
    label: "Xcode Build",
    description:
      "Build an Xcode project or workspace using xcode-cli. " +
      "Auto-discovers project, workspace, and scheme when not specified. " +
      "Returns parsed build errors/warnings in a compact format.",
    promptSnippet: "Build Xcode projects with xcode-cli (auto-discovers project/scheme)",
    promptGuidelines: [
      "Use xcode_build to compile Xcode projects instead of running xcodebuild directly.",
      "Omit scheme/project/workspace to let xcode-cli auto-discover them from the current directory.",
    ],
    parameters: Type.Object({
      scheme: Type.Optional(Type.String({ description: "Build scheme (auto-discovered if omitted)" })),
      configuration: Type.Optional(Type.String({ description: "Debug or Release (default: Debug)" })),
      destination: Type.Optional(
        Type.String({ description: "Build destination, e.g. 'platform=iOS Simulator,name=iPhone 16'" })
      ),
      filter: Type.Optional(Type.String({ description: "Output filter: all, issues, errors (default: errors)" })),
      workspace: Type.Optional(Type.String({ description: "Path to .xcworkspace" })),
      project: Type.Optional(Type.String({ description: "Path to .xcodeproj" })),
    }),

    renderCall(args: any, theme: any) {
      const parts: string[] = [];
      if (args.scheme) parts.push(args.scheme);
      parts.push(args.configuration ?? "Debug");
      if (args.destination) parts.push(args.destination);
      let text = theme.fg("toolTitle", theme.bold("xcode_build "));
      if (parts.length) text += theme.fg("muted", parts.join(" | "));
      return new Text(text, 0, 0);
    },

    renderResult(result: any, { expanded, isPartial }: any, theme: any) {
      if (isPartial) {
        const status = result.details?.status;
        return new Text(status ? theme.fg("warning", status) : theme.fg("dim", "Starting..."), 0, 0);
      }
      const content = result.content?.[0]?.text ?? "";
      const success = result.details?.success;
      if (success) {
        const lines = content.split("\n");
        const summary = lines[0] ?? "✓ Build Succeeded";
        if (!expanded || lines.length <= 1) return new Text(theme.fg("success", summary), 0, 0);
        let text = theme.fg("success", summary);
        for (const line of lines.slice(1)) text += "\n" + theme.fg("dim", line);
        return new Text(text, 0, 0);
      }
      return new Text(theme.fg("error", content), 0, 0);
    },

    async execute(_toolCallId, params: any, signal, onUpdate, ctx) {
      const config = params.configuration ?? "Debug";
      const { label, destination, commit, uncommitted } = await resolveInfo(pi, params, signal);
      const base = buildStatusBase(label, config, destination, commit, uncommitted);

      const t = (ctx.ui as any).theme;
      ctx.ui.setStatus("xcode-build", t.fg("warning", `⏳ Building ${base}`));
      onUpdate?.({ content: [{ type: "text", text: `⏳ Building ${base}` }], details: { status: `⏳ Building ${base}` } });

      const buildArgs: string[] = ["build", "--json"];
      addProjectArgs(buildArgs, params);
      if (params.configuration) buildArgs.push("-c", params.configuration);
      if (params.destination) buildArgs.push("-d", params.destination);
      if (params.filter) buildArgs.push("-f", params.filter);

      const buildResult = await pi.exec("xcode-cli", buildArgs, { signal });

      let success = buildResult.code === 0;
      let output = "";
      let errorCount = 0;
      let warningCount = 0;

      try {
        const json = JSON.parse(buildResult.stdout);
        success = json.success;
        output = json.output ?? "";
        errorCount = json.errorCount ?? 0;
        warningCount = json.warningCount ?? 0;
      } catch {
        output = (buildResult.stdout + buildResult.stderr).trim();
      }

      const icon = success ? "✓" : "✗";
      const issues = formatIssues(errorCount, warningCount);
      ctx.ui.setStatus("xcode-build", success
        ? t.fg("success", `${icon} ${base}${issues}`)
        : t.fg("error", `${icon} ${base}${issues}`));

      const finalOutput = truncateOutput(output);
      return {
        content: [{ type: "text", text: finalOutput || (success ? "✓ Build Succeeded" : "✗ Build Failed") }],
        details: { success, exitCode: buildResult.code, errorCount, warningCount },
      };
    },
  });

  // ── xcode_run ────────────────────────────────────────────────────────

  pi.registerTool({
    name: "xcode_run",
    label: "Xcode Run",
    description:
      "Build, install, and launch an app on the iOS Simulator using xcode-cli. " +
      "Auto-discovers project, workspace, and scheme when not specified. " +
      "Returns build errors/warnings and launch status.",
    promptSnippet: "Build and run iOS apps on the Simulator (auto-discovers project/scheme/simulator)",
    promptGuidelines: [
      "Use xcode_run to build and launch iOS apps on the Simulator instead of manual xcodebuild + simctl steps.",
      "Omit scheme/project/workspace/simulator to let xcode-cli auto-discover them.",
    ],
    parameters: Type.Object({
      scheme: Type.Optional(Type.String({ description: "Build scheme (auto-discovered if omitted)" })),
      configuration: Type.Optional(Type.String({ description: "Debug or Release (default: Debug)" })),
      simulator: Type.Optional(Type.String({ description: "Simulator name or UDID (default: latest iPhone)" })),
      skipBuild: Type.Optional(Type.Boolean({ description: "Skip the build step (default: false)" })),
      console: Type.Optional(Type.Boolean({ description: "Stream console logs to a file (default: true)" })),
      workspace: Type.Optional(Type.String({ description: "Path to .xcworkspace" })),
      project: Type.Optional(Type.String({ description: "Path to .xcodeproj" })),
    }),

    renderCall(args: any, theme: any) {
      const parts: string[] = [];
      if (args.scheme) parts.push(args.scheme);
      parts.push(args.configuration ?? "Debug");
      if (args.simulator) parts.push(args.simulator);
      let text = theme.fg("toolTitle", theme.bold("xcode_run "));
      if (parts.length) text += theme.fg("muted", parts.join(" | "));
      return new Text(text, 0, 0);
    },

    renderResult(result: any, { expanded, isPartial }: any, theme: any) {
      if (isPartial) {
        const status = result.details?.status;
        return new Text(status ? theme.fg("warning", status) : theme.fg("dim", "Starting..."), 0, 0);
      }
      const content = result.content?.[0]?.text ?? "";
      const success = result.details?.success;
      if (success) {
        const lines = content.split("\n");
        const summary = lines[0] ?? "✓ Launched";
        if (!expanded || lines.length <= 1) return new Text(theme.fg("success", summary), 0, 0);
        let text = theme.fg("success", summary);
        for (const line of lines.slice(1)) text += "\n" + theme.fg("dim", line);
        return new Text(text, 0, 0);
      }
      return new Text(theme.fg("error", content), 0, 0);
    },

    async execute(_toolCallId, params: any, signal, onUpdate, ctx) {
      const config = params.configuration ?? "Debug";
      const { label, commit, uncommitted } = await resolveInfo(pi, params, signal);

      // During build phase, we don't know the simulator yet
      const gitPart = commit ? ` | ${commit}` : "";
      const dirtyPart = commit ? (uncommitted > 0 ? ` | ${uncommitted} uncommitted` : " | clean") : "";

      const t = (ctx.ui as any).theme;
      const buildingStatus = `⏳ Building ${label} | ${config}${gitPart}${dirtyPart}`;
      ctx.ui.setStatus("xcode-run", t.fg("warning", buildingStatus));
      onUpdate?.({ content: [{ type: "text", text: buildingStatus }], details: { status: buildingStatus } });

      const wantConsole = params.console !== false;

      // Build + install (+ launch when console is off)
      // When console is on, --wait skips launch so console command can do it with stdout capture
      const runArgs: string[] = ["run", "--json", "--no-debug", "--no-console"];
      if (wantConsole) runArgs.push("--wait");
      addProjectArgs(runArgs, params);
      if (params.configuration) runArgs.push("-c", params.configuration);
      if (params.simulator) runArgs.push("--simulator", params.simulator);
      if (params.skipBuild) runArgs.push("--skip-build");

      const runResult = await pi.exec("xcode-cli", runArgs, { signal });

      let success = runResult.code === 0;
      let simulator = params.simulator ?? "";
      let simulatorOS = "";
      let deviceUDID = "";
      let bundleId = "";
      let buildOutput = "";
      let errorCount = 0;
      let warningCount = 0;
      let launched = false;
      let appPid = 0;
      let error = "";

      try {
        const json = JSON.parse(runResult.stdout);
        success = json.success ?? success;
        simulator = json.simulator ?? simulator;
        simulatorOS = json.simulatorOS ?? "";
        deviceUDID = json.deviceUDID ?? "";
        bundleId = json.bundleId ?? "";
        if (bundleId) currentBundleId = bundleId;
        buildOutput = json.buildOutput ?? "";
        errorCount = json.errorCount ?? 0;
        warningCount = json.warningCount ?? 0;
        launched = json.launched ?? false;
        appPid = json.appPid ?? 0;
        error = json.error ?? "";
      } catch {
        buildOutput = (runResult.stdout + runResult.stderr).trim();
      }

      // Final status with simulator name + OS version from the run result
      const simLabel = simulator ? (simulatorOS ? `${simulator} (${simulatorOS})` : simulator) : "";
      const simPart = simLabel ? ` | ${simLabel}` : "";
      const base = `${label} | ${config}${simPart}${gitPart}${dirtyPart}`;
      const issues = formatIssues(errorCount, warningCount);
      let logFile = "";

      if (success && wantConsole && deviceUDID && bundleId) {
        // Console mode: spawn console --launch (handles launch + stdout + log stream)
        stopMonitor();
        stopConsole();

        // Use a timestamp-based log file (PID not known yet — console does the launch)
        logFile = `${LOG_FILE_PREFIX}${Date.now()}.log`;
        currentLogFile = logFile;
        try {
          const child = spawn("xcode-cli", [
            "console",
            "--device-udid", deviceUDID,
            "--bundle-id", bundleId,
            "--launch",
            "--log-file", logFile,
          ], { stdio: "ignore", detached: true });
          child.on("error", () => {});
          child.unref();
          consolePid = child.pid ?? null;

          // Monitor the console process — when it dies, app has terminated
          ctx.ui.setStatus("xcode-run", t.fg("success", `▶ Running ${base}${issues}`));
          const ui = ctx.ui;
          const cPid = consolePid;
          if (cPid) {
            appMonitor = setInterval(() => {
              try {
                process.kill(cPid, 0);
              } catch {
                ui.setStatus("xcode-run", t.fg("dim", `■ Stopped ${base}${issues}`));
                stopMonitor();
              }
            }, 1000);
          }
          launched = true;
        } catch {
          logFile = "";
        }
      } else if (success && launched && appPid) {
        // No-console mode: app already launched by run command — just monitor PID
        stopMonitor();
        stopConsole();
        ctx.ui.setStatus("xcode-run", t.fg("success", `▶ Running ${base}${issues}`));
        const ui = ctx.ui;
        appMonitor = setInterval(() => {
          try {
            process.kill(appPid, 0);
          } catch {
            ui.setStatus("xcode-run", t.fg("dim", `■ Stopped ${base}${issues}`));
            stopMonitor();
          }
        }, 1000);
      } else {
        stopMonitor();
        stopConsole();
        const icon = success ? "✓" : "✗";
        ctx.ui.setStatus("xcode-run", success
          ? t.fg("success", `${icon} ${base}${issues}`)
          : t.fg("error", `${icon} ${base}${issues}`));
      }

      // Build output text for LLM
      let output = "";
      if (buildOutput) output += buildOutput;
      if (launched) output += (output ? "\n" : "") + `✓ Launched on ${simLabel || "Simulator"}`;
      if (logFile) output += `\nConsole logs: ${logFile}`;
      if (error) output += (output ? "\n" : "") + `Error: ${error}`;
      if (!output) output = success ? "✓ Launched" : "✗ Run Failed";

      const finalOutput = truncateOutput(output);
      return {
        content: [{ type: "text", text: finalOutput }],
        details: { success, launched, simulator, logFile, exitCode: runResult.code, errorCount, warningCount },
      };
    },
  });

  // ── xcode_console ──────────────────────────────────────────────────

  pi.registerTool({
    name: "xcode_console",
    label: "Xcode Console",
    description:
      "Read console logs from a running or recently-run iOS Simulator app. " +
      "Filters by grep pattern (defaults to errors/crashes). " +
      "Use after xcode_run to inspect app behavior.",
    promptSnippet: "Read iOS Simulator console logs (grep for errors by default)",
    promptGuidelines: [
      "Use xcode_console to check app logs after xcode_run — it greps the log file efficiently.",
      "Default filter catches errors and crashes. Pass a custom grep for specific messages.",
    ],
    parameters: Type.Object({
      grep: Type.Optional(Type.String({ description: "Grep pattern (default: errors/crashes). Use '.' to show all logs." })),
      tail: Type.Optional(Type.Number({ description: "Number of lines from the end (default: all matching)" })),
    }),

    renderCall(args: any, theme: any) {
      const pattern = args.grep ?? "errors";
      let text = theme.fg("toolTitle", theme.bold("xcode_console "));
      text += theme.fg("muted", pattern);
      return new Text(text, 0, 0);
    },

    renderResult(result: any, { expanded, isPartial }: any, theme: any) {
      const content = result.content?.[0]?.text ?? "";
      const lines = content.split("\n");
      const summary = lines[0] ?? "";
      if (!expanded || lines.length <= 1) return new Text(theme.fg("dim", summary), 0, 0);
      let text = summary;
      for (const line of lines.slice(1)) text += "\n" + theme.fg("dim", line);
      return new Text(text, 0, 0);
    },

    async execute(_toolCallId, params: any, signal) {
      if (!currentLogFile) {
        return { content: [{ type: "text", text: "No console log file. Run an app first with xcode_run." }] };
      }

      const pattern = params.grep ?? "error|crash|fault|fatal|exception";
      const tailN = params.tail;

      // Use grep to filter, optionally pipe through tail
      let cmd = `grep -iE '${pattern.replace(/'/g, "'\\''")}' '${currentLogFile}'`;
      if (tailN) cmd += ` | tail -n ${tailN}`;

      const result = await pi.exec("bash", ["-c", cmd], { signal, timeout: 10_000 });

      const output = result.stdout.trim();
      if (!output) {
        return { content: [{ type: "text", text: `No matches for '${pattern}' in console logs.` }] };
      }

      const finalOutput = truncateOutput(output);
      const lineCount = output.split("\n").length;
      return {
        content: [{ type: "text", text: `${lineCount} matching line${lineCount > 1 ? "s" : ""}:\n${finalOutput}` }],
      };
    },
  });

  // ── xcode_debug ──────────────────────────────────────────────────

  pi.registerTool({
    name: "xcode_debug",
    label: "Xcode Debug",
    description:
      "Run LLDB debugger commands on a running or crashed iOS Simulator app. " +
      "Auto-starts a debug session if none exists. " +
      "The app process is paused while LLDB commands run. " +
      "Use 'process interrupt' to pause a running app, 'process continue' to resume.",
    promptSnippet: "Run LLDB commands on the app (bt, frame variable, p expression, breakpoint set, etc.)",
    promptGuidelines: [
      "Use xcode_debug to inspect app state, investigate crashes, and run LLDB commands.",
      "The app must be paused to inspect threads/variables. Use 'process interrupt' first if it's running.",
      "After inspection, use 'process continue' to resume the app.",
      "Common commands: 'bt' (backtrace), 'frame variable' (locals), 'thread list', 'p <expr>' (evaluate).",
      "For breakpoints: 'breakpoint set -f File.swift -l 42', then 'process continue' to hit it.",
    ],
    parameters: Type.Object({
      commands: Type.Array(Type.String(), {
        description: "LLDB commands to execute (e.g., ['process interrupt', 'bt', 'frame variable'])",
      }),
    }),

    renderCall(args: any, theme: any) {
      const cmds = args.commands ?? [];
      let text = theme.fg("toolTitle", theme.bold("xcode_debug "));
      text += theme.fg("muted", cmds.join(" → "));
      return new Text(text, 0, 0);
    },

    renderResult(result: any, { expanded }: any, theme: any) {
      const content = result.content?.[0]?.text ?? "";
      const lines = content.split("\n");
      const summary = lines[0] ?? "";
      if (!expanded || lines.length <= 3) return new Text(theme.fg("dim", summary), 0, 0);
      let text = summary;
      for (const line of lines.slice(1)) text += "\n" + theme.fg("dim", line);
      return new Text(text, 0, 0);
    },

    async execute(_toolCallId, params: any, signal) {
      const commands: string[] = params.commands ?? [];
      if (!commands.length) {
        return { content: [{ type: "text", text: "No commands provided." }] };
      }

      // Auto-start debug session if none exists
      const statusResult = await pi.exec("xcode-cli", ["debug", "status", "--json"], { signal, timeout: 10_000 });
      let active = false;
      try { active = JSON.parse(statusResult.stdout).active === true; } catch {}

      if (!active) {
        // Try to find the app and start a session
        const appName = currentBundleId?.split(".").pop() ?? "";
        if (!appName) {
          return { content: [{ type: "text", text: "No app running. Use xcode_run first, then xcode_debug." }] };
        }

        const startResult = await pi.exec("xcode-cli", ["debug", "start", "--app-name", appName], {
          signal, timeout: 15_000,
        });
        if (startResult.code !== 0) {
          return {
            content: [{ type: "text", text: `Failed to start debug session: ${(startResult.stdout + startResult.stderr).trim()}` }],
          };
        }
      }

      // Execute commands
      const args = ["debug", "exec", "--json", ...commands];
      const result = await pi.exec("xcode-cli", args, { signal, timeout: 60_000 });

      if (result.code !== 0) {
        return { content: [{ type: "text", text: `Debug exec failed: ${(result.stdout + result.stderr).trim()}` }] };
      }

      // Format output
      let output = "";
      try {
        const json = JSON.parse(result.stdout);
        for (const r of json.results ?? []) {
          output += `(lldb) ${r.command}\n`;
          if (r.output) output += r.output + (r.output.endsWith("\n") ? "" : "\n");
        }
      } catch {
        output = result.stdout;
      }

      if (!output.trim()) output = "Commands executed (no output).";

      const finalOutput = truncateOutput(output.trim());
      return { content: [{ type: "text", text: finalOutput }] };
    },
  });
}
