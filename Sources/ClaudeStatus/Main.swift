import Foundation

@main
enum Main {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.runBlocking(arguments: CommandLine.arguments)
        }
        ClaudeStatusApp.main()
    }
}
