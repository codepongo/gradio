# GradioClient (Swift)

Swift version of Gradio Client, referencing `client/python/gradio_client`, for easily calling Gradio app APIs in iOS/macOS.

Currently implemented:

- Connect to remote Gradio app (via URL)
- Fetch `/config` and `/info`, infer available API endpoints
- Synchronous call `predict(args:apiName:)`

## 1. SDK Integration Example (iOS / macOS App)

Assuming you're adding this package in Xcode via Swift Package Manager (local path or Git repository address both work):

1. In Xcode menu, select: **File → Add Packages...**
2. Enter repository address or local path, add the `GradioClient` package
3. Check the `GradioClient` library in your App target

Then use it in your code like this:

```swift
import UIKit
import GradioClient

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        Task {
            do {
                // Connect to remote Gradio app
                let client = try await GradioClient.connect(
                    src: "https://your-app.gradio.live"
                )

                // Print available API information (view in Xcode console)
                client.printAPIInfo()

                // Call the endpoint named "/predict"
                let result = try await client.predict(
                    args: ["Hello from iOS"],
                    apiName: "/predict"
                )
                print("Result:", result)
            } catch {
                print("Gradio error:", error)
            }
        }
    }
}
```

> Note:
>
> - The order of the `args` array must match the order of input components in the corresponding endpoint in the Gradio app. You can check this by calling `printAPIInfo()` first.
> - If the endpoint has only one output, `result` will be a single value; otherwise it returns `[Any]`.

## 2. Command Line Example (GradioClientCLI)

This package also includes an executable target: `GradioClientCLI`, which can be used to directly call Gradio applications from the command line.

### 2.1 Build CLI

Run in the repository root:

```bash
cd client/swift
swift build -c release
```

After compilation, the executable will be located approximately at:

```bash
.build/release/GradioClientCLI
```

### 2.2 Usage

```bash
./.build/release/GradioClientCLI <gradio_url> <api_name> [args...]
```

Example:

```bash
./.build/release/GradioClientCLI \
  https://your-app.gradio.live \
  /predict \
  "Hello from CLI"
```

The program will:

1. Connect to the specified Gradio URL
2. Print available API endpoint information
3. Call the given `api_name`, treating all subsequent parameters as string inputs
4. Print `Result: ...` to standard output

If you want to use it in shell scripts, you can directly capture stdout or determine if the call was successful through the return code (exit code is 1 on error).

