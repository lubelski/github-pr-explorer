import Foundation

@main
struct GitHubPRExplorerControl {
    static func main() {
        let result = ControlCommand.run(Array(CommandLine.arguments.dropFirst()))
        if !result.output.isEmpty {
            FileHandle.standardOutput.write(Data(result.output.utf8))
        }
        if !result.errorOutput.isEmpty {
            FileHandle.standardError.write(Data(result.errorOutput.utf8))
        }
        exit(result.exitCode)
    }
}
