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

  function stopMonitor() {
    if (appMonitor) { clearInterval(appMonitor); appMonitor = null; }
  }

  pi.on("session_shutdown", async () => { stopMonitor(); });
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

      ctx.ui.setStatus("xcode-build", `⏳ Building ${base}`);
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
      ctx.ui.setStatus("xcode-build", `${icon} ${base}${formatIssues(errorCount, warningCount)}`);

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

      const buildingStatus = `⏳ Building ${label} | ${config}${gitPart}${dirtyPart}`;
      ctx.ui.setStatus("xcode-run", buildingStatus);
      onUpdate?.({ content: [{ type: "text", text: buildingStatus }], details: { status: buildingStatus } });

      // Run with JSON (--no-debug --no-console for non-interactive)
      const runArgs: string[] = ["run", "--json", "--no-debug", "--no-console"];
      addProjectArgs(runArgs, params);
      if (params.configuration) runArgs.push("-c", params.configuration);
      if (params.simulator) runArgs.push("--simulator", params.simulator);
      if (params.skipBuild) runArgs.push("--skip-build");

      const runResult = await pi.exec("xcode-cli", runArgs, { signal });

      let success = runResult.code === 0;
      let simulator = params.simulator ?? "";
      let simulatorOS = "";
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

      if (success && launched && appPid) {
        // App is running — monitor the PID
        stopMonitor();
        ctx.ui.setStatus("xcode-run", `🟢 Running ${base}${issues}`);
        const ui = ctx.ui;
        appMonitor = setInterval(() => {
          try {
            process.kill(appPid, 0); // signal 0 = check if alive
          } catch {
            ui.setStatus("xcode-run", `🔴 Stopped ${base}${issues}`);
            stopMonitor();
          }
        }, 1000);
      } else {
        stopMonitor();
        const icon = success ? "✓" : "✗";
        ctx.ui.setStatus("xcode-run", `${icon} ${base}${issues}`);
      }

      // Build output text for LLM
      let output = "";
      if (buildOutput) output += buildOutput;
      if (launched) output += (output ? "\n" : "") + `✓ Launched on ${simLabel || "Simulator"}`;
      if (error) output += (output ? "\n" : "") + `Error: ${error}`;
      if (!output) output = success ? "✓ Launched" : "✗ Run Failed";

      const finalOutput = truncateOutput(output);
      return {
        content: [{ type: "text", text: finalOutput }],
        details: { success, launched, simulator, exitCode: runResult.code, errorCount, warningCount },
      };
    },
  });
}
