# GradioClient (Swift) Changelog

## 0.1.0

- Initial experimental Swift client, mirroring a subset of the Python and JS client features:
  - Connect to a remote Gradio app via URL
  - Fetch `/config` and `/info`
  - Call `predict(args:apiName:)` for non-streaming endpoints
  - Provide a simple CLI tool `GradioClientCLI` for command-line usage

