import Foundation

@main
struct GitHubPRExplorerControl {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        // `mcp` serves until standard input closes, answering each line as it arrives.
        if let result = ControlCommand.serveMCPIfAsked(arguments, sourceFromSettings: true, input: { readLine(strippingNewline: true) },
                                                       output: { line in FileHandle.standardOutput.write(Data((line + "\n").utf8)) }) {
            finish(result)
        }
        // list and show follow the pullRequestSource setting when --source is not given.
        finish(await ControlCommand.runAsync(arguments, sourceFromSettings: true))
    }

    static func finish(_ result: ControlCommandResult) -> Never {
        if !result.output.isEmpty {
            FileHandle.standardOutput.write(Data(result.output.utf8))
        }
        if !result.errorOutput.isEmpty {
            FileHandle.standardError.write(Data(result.errorOutput.utf8))
        }
        exit(result.exitCode)
    }
}
