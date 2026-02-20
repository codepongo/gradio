import Foundation
import GradioClient

@main
struct GradioClientCommand {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else {
            print("Usage: GradioClientCLI <gradio_url> <api_name> [--username <username> --password <password>] [args...]")
            print("Example: GradioClientCLI https://example.gradio.live /predict \"Hello\"")
            print("Example with auth: GradioClientCLI https://example.gradio.live /predict --username user --password pass \"Hello\"")
            return
        }

        let url = arguments[1]
        let apiName = arguments[2]
        var rawArgs = Array(arguments.dropFirst(3))
        
        // Parse authentication arguments
        var auth: (String, String)? = nil
        var authIndex: Int? = nil
        
        for (index, arg) in rawArgs.enumerated() {
            if arg == "--username" && index + 1 < rawArgs.count {
                let username = rawArgs[index + 1]
                if index + 2 < rawArgs.count && rawArgs[index + 2] == "--password" && index + 3 < rawArgs.count {
                    let password = rawArgs[index + 3]
                    auth = (username, password)
                    authIndex = index
                    break
                }
            }
        }
        
        // Remove auth arguments from rawArgs
        if let authIndex = authIndex {
            rawArgs.removeSubrange(authIndex..<authIndex + 4)
        }

        do {
            let client = try await GradioClient.connect(src: url, auth: auth)
            client.printAPIInfo()

            let result = try await client.predict(
                args: rawArgs,
                apiName: apiName
            )
            print("Result:", result)
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }
}

