import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "xcode_build",
    label: "Xcode Build",
    description:
      "Build an Xcode project or workspace using xcode-cli. " +
      "Auto-discovers project, workspace, and scheme when not specified. " +
      "Returns parsed build errors/warnings in a compact format.",
    parameters: Type.Object({
      project: Type.Optional(Type.String({ description: "Path to .xcodeproj" })),
      workspace: Type.Optional(Type.String({ description: "Path to .xcworkspace" })),
      scheme: Type.Optional(Type.String({ description: "Build scheme (auto-discovered if omitted)" })),
      configuration: Type.Optional(Type.String({ description: "Debug or Release (default: Debug)" })),
      destination: Type.Optional(
        Type.String({
          description: "Build destination, e.g. 'platform=iOS Simulator,name=iPhone 16'",
        })
      ),
      filter: Type.Optional(
        Type.String({
          description: "Output filter: all, issues, errors (default: errors)",
        })
      ),
    }),

    async execute(_toolCallId, _params, _signal, _onUpdate, _ctx) {
      // TODO: implement build logic
      return {
        content: [{ type: "text", text: "xcode_build: not yet implemented" }],
        details: {},
      };
    },
  });
}
