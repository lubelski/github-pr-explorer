import Foundation

@main
struct GitHubPRExplorerControl {
    static func main() async {
        // list and show follow the pullRequestSource setting when --source is not given.
        let result = await ControlCommand.runAsync(Array(CommandLine.arguments.dropFirst()), sourceFromSettings: true)
        if !result.output.isEmpty {
            FileHandle.standardOutput.write(Data(result.output.utf8))
        }
        if !result.errorOutput.isEmpty {
            FileHandle.standardError.write(Data(result.errorOutput.utf8))
        }
        exit(result.exitCode)
    }
}
