/**
 * Xcode Build Extension for pi
 *
 * Registers an `xcode_build` tool that builds Xcode projects via xcode-cli.
 * Shows ⏳ status with project name, config, git commit, and dirty state during build.
 * Persists ✓/✗ status with error/warning counts after build.
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

export default function (pi: ExtensionAPI) {
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

      // 1. Resolve project info + git state
      const infoArgs: string[] = ["info"];
      addProjectArgs(infoArgs, params);

      let label = params.scheme ?? "project";
      let commit = "";
      let uncommitted = 0;

      const infoResult = await pi.exec("xcode-cli", infoArgs, { signal, timeout: 15_000 });
      if (infoResult.code === 0) {
        try {
          const info = JSON.parse(infoResult.stdout);
          label = info.label ?? label;
          commit = info.commit ?? "";
          uncommitted = info.uncommitted ?? 0;
        } catch {}
      }

      // 2. Status parts (reused for both ⏳ and ✓/✗)
      const destPart = params.destination ? ` | ${params.destination}` : "";
      const gitPart = commit ? ` | ${commit}` : "";
      const dirtyPart = commit ? (uncommitted > 0 ? ` | ${uncommitted} uncommitted` : " | clean") : "";
      const base = `${label} | ${config}${destPart}${gitPart}${dirtyPart}`;

      // 3. Show building status
      ctx.ui.setStatus("xcode-build", `⏳ ${base}`);
      onUpdate?.({
        content: [{ type: "text", text: `⏳ ${base}` }],
        details: { status: `⏳ ${base}` },
      });

      // 4. Build with JSON output
      const buildArgs: string[] = ["build", "--json"];
      addProjectArgs(buildArgs, params);
      if (params.configuration) buildArgs.push("-c", params.configuration);
      if (params.destination) buildArgs.push("-d", params.destination);
      if (params.filter) buildArgs.push("-f", params.filter);

      const buildResult = await pi.exec("xcode-cli", buildArgs, { signal });

      // 5. Parse structured result
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

      // 6. Final persistent status: ✓/✗ Label | Config | commit | dirty | errors/warnings
      const icon = success ? "✓" : "✗";
      const issuePart = errorCount > 0 || warningCount > 0 ? ` | ${errorCount}E ${warningCount}W` : "";
      ctx.ui.setStatus("xcode-build", `${icon} ${base}${issuePart}`);

      // 7. Truncate output for LLM
      const truncation = truncateTail(output, { maxLines: DEFAULT_MAX_LINES, maxBytes: DEFAULT_MAX_BYTES });
      let finalOutput = truncation.content;
      if (truncation.truncated) {
        finalOutput += `\n\n[Output truncated: ${truncation.outputLines} of ${truncation.totalLines} lines`;
        finalOutput += ` (${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)})]`;
      }

      return {
        content: [{ type: "text", text: finalOutput || (success ? "✓ Build Succeeded" : "✗ Build Failed") }],
        details: { success, exitCode: buildResult.code, errorCount, warningCount },
      };
    },
  });
}
