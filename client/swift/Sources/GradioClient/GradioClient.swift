import Foundation

public enum GradioClientError: Error {
    case invalidURL(String)
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case jsonDecodeError(Error)
    case apiError(String)
    case configMissingAPIInfo
    case apiNameNotFound(String)
    case authenticationError(String)
}

/// 极简版 Gradio Swift 客户端，参考 `client/python/gradio_client/client.py`
/// 目前支持：
/// - 连接到一个 Gradio app（通过 URL）
/// - 拉取 `/config` 和 `/info`
/// - 使用 `predict` 进行同步调用
public final class GradioClient {
    public let src: URL
    public let apiPrefix: String
    public let srcPrefixed: URL
    public let apiURL: URL
    public let sseURL: URL

    public let rawConfig: [String: Any]
    public let apiInfo: [String: Any]

    private let headers: [String: String]
    private let cookies: [String: String]
    private let urlSession: URLSession

    // MARK: - 初始化 / 连接

    /// 主入口：类似 Python 的 `Client("https://...")`
    @discardableResult
    public static func connect(
        src: String,
        headers: [String: String] = [:],
        auth: (String, String)? = nil,
        urlSession: URLSession = .shared
    ) async throws -> GradioClient {
        guard var url = URL(string: src) else {
            throw GradioClientError.invalidURL(src)
        }
        if !url.absoluteString.hasSuffix("/") {
            url = url.appendingPathComponent("")
        }
        
        var cookies: [String: String] = [:]
        
        // Handle authentication like Python client
        if let auth = auth {
            cookies = try await login(src: url, username: auth.0, password: auth.1, urlSession: urlSession)
        }

        let configURL = url.appendingPathComponent("config", isDirectory: false)
        var configRequest = URLRequest(url: configURL)
        headers.forEach { key, value in
            configRequest.setValue(value, forHTTPHeaderField: key)
        }
        cookies.forEach { key, value in
            configRequest.setValue("\(key)=\(value)", forHTTPHeaderField: "Cookie")
        }
        let (configData, configResponse) = try await urlSession.data(for: configRequest)
        try GradioClient.checkHTTP(response: configResponse, data: configData)

        let rawConfigAny = try JSONSerialization.jsonObject(with: configData, options: [])
        guard let rawConfig = rawConfigAny as? [String: Any] else {
            throw GradioClientError.invalidResponse
        }

        let apiPrefixRaw = (rawConfig["api_prefix"] as? String ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiPrefix = apiPrefixRaw.isEmpty ? "" : apiPrefixRaw + "/"
        let srcPrefixed = url.appendingPathComponent(apiPrefix, isDirectory: true)

        let apiInfoURL = srcPrefixed.appendingPathComponent("info", isDirectory: false)
        var infoRequest = URLRequest(url: apiInfoURL)
        headers.forEach { key, value in
            infoRequest.setValue(value, forHTTPHeaderField: key)
        }
        cookies.forEach { key, value in
            infoRequest.setValue("\(key)=\(value)", forHTTPHeaderField: "Cookie")
        }
        let (infoData, infoResponse) = try await urlSession.data(for: infoRequest)
        try GradioClient.checkHTTP(response: infoResponse, data: infoData)
        let apiInfoAny = try JSONSerialization.jsonObject(with: infoData, options: [])
        guard let apiInfo = apiInfoAny as? [String: Any] else {
            throw GradioClientError.invalidResponse
        }

        return GradioClient(
            src: url,
            apiPrefix: apiPrefix,
            srcPrefixed: srcPrefixed,
            rawConfig: rawConfig,
            apiInfo: apiInfo,
            headers: headers,
            cookies: cookies,
            urlSession: urlSession
        )
    }

    private init(
        src: URL,
        apiPrefix: String,
        srcPrefixed: URL,
        rawConfig: [String: Any],
        apiInfo: [String: Any],
        headers: [String: String],
        cookies: [String: String],
        urlSession: URLSession
    ) {
        self.src = src
        self.apiPrefix = apiPrefix
        self.srcPrefixed = srcPrefixed
        self.rawConfig = rawConfig
        self.apiInfo = apiInfo
        self.headers = headers
        self.cookies = cookies
        self.urlSession = urlSession

        self.apiURL = srcPrefixed.appendingPathComponent("api/predict", isDirectory: false)
        self.sseURL = srcPrefixed.appendingPathComponent("queue/join", isDirectory: false)
    }

    // MARK: - 公共方法

    /// 等价于 Python 中的 Client.predict（同步调用，不做 streaming）
    /// - Parameters:
    ///   - args: 输入参数列表，顺序需与 Gradio app 输入组件一致
    ///   - apiName: 形如 "/predict" 的命名 endpoint
    public func predict(
        args: [Any],
        apiName: String
    ) async throws -> Any {
        let fnIndex = try inferFnIndex(apiName: apiName)

        let payload: [String: Any] = [
            "data": args,
            "fn_index": fnIndex,
            "session_hash": UUID().uuidString
        ]
        // 保留给后续扩展（如在 payload 中加入队列相关参数）
        _ = payload

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        cookies.forEach { key, value in
            request.setValue("\(key)=\(value)", forHTTPHeaderField: "Cookie")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)
        try GradioClient.checkHTTP(response: response, data: data)

        let jsonAny = try JSONSerialization.jsonObject(with: data, options: [])
        guard let json = jsonAny as? [String: Any] else {
            throw GradioClientError.invalidResponse
        }

        if let error = json["error"] as? String, !error.isEmpty {
            throw GradioClientError.apiError(error)
        }
        guard let dataArr = json["data"] as? [Any] else {
            throw GradioClientError.invalidResponse
        }
        if dataArr.count == 1 {
            return dataArr[0]
        } else {
            return dataArr
        }
    }

    /// 打印可用的命名 endpoint 信息，类似 Python 的 view_api(print_info=True)
    public func printAPIInfo(allEndpoints: Bool = false) {
        guard
            let named = apiInfo["named_endpoints"] as? [String: Any]
        else {
            print("No API info available.")
            return
        }
        let unnamed = apiInfo["unnamed_endpoints"] as? [String: Any] ?? [:]

        print("GradioClient.predict() Usage Info")
        print("---------------------------")
        print("Named API endpoints: \(named.count)")
        for (name, infoAny) in named {
            guard let info = infoAny as? [String: Any] else { continue }
            renderEndpoint(nameOrIndex: name, info: info)
        }

        if allEndpoints {
            print("\nUnnamed API endpoints: \(unnamed.count)")
            for (idx, infoAny) in unnamed {
                guard let info = infoAny as? [String: Any] else { continue }
                renderEndpoint(nameOrIndex: idx, info: info)
            }
        } else if !unnamed.isEmpty {
            print("\nUnnamed API endpoints: \(unnamed.count), call printAPIInfo(allEndpoints: true) to see them.")
        }
    }

    // MARK: - 辅助方法

    private func inferFnIndex(apiName: String) throws -> Int {
        guard
            let named = apiInfo["named_endpoints"] as? [String: Any]
        else {
            throw GradioClientError.configMissingAPIInfo
        }
        guard let endpoint = named[apiName] as? [String: Any] else {
            throw GradioClientError.apiNameNotFound(apiName)
        }
        if let fnIndex = endpoint["fn_index"] as? Int {
            return fnIndex
        }
        if let deps = rawConfig["dependencies"] as? [[String: Any]] {
            for (i, dep) in deps.enumerated() {
                if let name = dep["api_name"] as? String, ("/" + name) == apiName {
                    if let id = dep["id"] as? Int {
                        return id
                    } else {
                        return i
                    }
                }
            }
        }
        throw GradioClientError.apiNameNotFound(apiName)
    }

    private func renderEndpoint(nameOrIndex: String, info: [String: Any]) {
        let parameters = info["parameters"] as? [[String: Any]] ?? []
        let returnsArr = info["returns"] as? [[String: Any]] ?? []

        let paramNames: [String] = parameters.compactMap { p in
            (p["parameter_name"] as? String) ?? (p["label"] as? String)
        }
        let retNames: [String] = returnsArr.compactMap { r in
            r["label"] as? String
        }

        let renderedParams = paramNames.joined(separator: ", ")
        let renderedReturns = retNames.joined(separator: ", ")

        print("\n - predict(\(renderedParams), api_name=\"\(nameOrIndex)\") -> \(renderedReturns)")
        print("    Parameters:")
        if parameters.isEmpty {
            print("     - None")
        } else {
            for p in parameters {
                let label = (p["parameter_name"] as? String) ?? (p["label"] as? String) ?? "param"
                let component = (p["component"] as? String) ?? "Unknown"
                let pyType = (p["python_type"] as? [String: Any])?["type"] as? String ?? "Any"
                print("     - [\(component)] \(label): \(pyType)")
            }
        }
        print("    Returns:")
        if returnsArr.isEmpty {
            print("     - None")
        } else {
            for r in returnsArr {
                let label = (r["label"] as? String) ?? "output"
                let component = (r["component"] as? String) ?? "Unknown"
                let pyType = (r["python_type"] as? [String: Any])?["type"] as? String ?? "Any"
                print("     - [\(component)] \(label): \(pyType)")
            }
        }
    }

    private func renderEndpoint(nameOrIndex: String, infoAny: Any) {
        guard let info = infoAny as? [String: Any] else { return }
        renderEndpoint(nameOrIndex: nameOrIndex, info: info)
    }

    private static func checkHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GradioClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GradioClientError.httpError(statusCode: http.statusCode, body: body)
        }
    }
    
    /// Login to get authentication cookies (similar to Python client's _login method)
    private static func login(src: URL, username: String, password: String, urlSession: URLSession) async throws -> [String: String] {
        let loginURL = src.appendingPathComponent("login", isDirectory: false)
        
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Create form data exactly like Python client with proper URL encoding
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let formData = "username=\(username.addingPercentEncoding(withAllowedCharacters: allowedChars) ?? username)&password=\(password.addingPercentEncoding(withAllowedCharacters: allowedChars) ?? password)"
        request.httpBody = formData.data(using: .utf8)
        
        print("🔍 Debug - Login Request:")
        print("URL: \(loginURL)")
        print("Body: \(formData)")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw GradioClientError.invalidResponse
        }
        
        print("🔍 Debug - Response Status: \(http.statusCode)")
        if let body = String(data: data, encoding: .utf8) {
            print("🔍 Debug - Response Body: \(body)")
        }
        
        if http.statusCode == 401 {
            throw GradioClientError.authenticationError("Invalid credentials for \(src)")
        } else if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GradioClientError.authenticationError("Could not login to \(src). Status: \(http.statusCode), Body: \(body)")
        }
        
        // Extract cookies from response
        guard let httpResponse = response as? HTTPURLResponse else {
            return [:]
        }
        
        var cookies: [String: String] = [:]
        
        // Get all cookies from response headers
        if let allHeaders = httpResponse.allHeaderFields as? [String: String] {
            for (key, value) in allHeaders {
                if key.lowercased() == "set-cookie" {
                    let cookiePairs = value.components(separatedBy: ",")
                    for cookiePair in cookiePairs {
                        let trimmedPair = cookiePair.trimmingCharacters(in: .whitespaces)
                        let components = trimmedPair.components(separatedBy: ";")
                        if let firstComponent = components.first {
                            let keyValue = firstComponent.components(separatedBy: "=")
                            if keyValue.count == 2 {
                                let cookieKey = keyValue[0].trimmingCharacters(in: .whitespaces)
                                let cookieValue = keyValue[1].trimmingCharacters(in: .whitespaces)
                                cookies[cookieKey] = cookieValue
                            }
                        }
                    }
                }
            }
        }
        
        print("🔍 Debug - Extracted Cookies: \(cookies)")
        return cookies
    }
}

