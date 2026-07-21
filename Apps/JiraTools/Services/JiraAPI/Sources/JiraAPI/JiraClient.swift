import Foundation
import JiraToolsFoundation

public struct ResolvedJiraLocation: Sendable {
    public let baseURL: URL
    public let jql: String

    public init(
        baseURL: URL,
        jql: String,
    ) {
        self.baseURL = baseURL
        self.jql = jql
    }
}

public final class JiraClient: Sendable {
    private let baseURL: URL
    private let authorization: String
    private let decoder: JSONDecoder
    private let session: URLSession

    public init(
        baseURL: URL,
        authorization: JiraAuthorization,
        extraFieldIDs: [String],
        session: URLSession = .shared,
    ) {
        self.baseURL = baseURL
        self.authorization = authorization.headerValue
        self.session = session

        let decoder = JSONDecoder()
        decoder.userInfo[.extraFieldIDs] = extraFieldIDs
        self.decoder = decoder
    }

    public func currentUser() async throws -> JiraUser {
        try await get(path: "/rest/api/3/myself", queryItems: [])
    }

    public func verifyConnection() async throws -> JiraUser {
        try await currentUser()
    }

    public func fields() async throws -> [JiraField] {
        try await get(path: "/rest/api/3/field", queryItems: [])
    }

    public func searchIssues(
        jql: String,
        maxResults: Int,
        fields: [String],
    ) async throws -> [JiraIssue] {
        var issues: [JiraIssue] = []
        var nextPageToken: String?

        repeat {
            var queryItems = [
                URLQueryItem(name: "jql", value: jql),
                URLQueryItem(name: "maxResults", value: String(maxResults)),
                URLQueryItem(name: "fields", value: fields.joined(separator: ",")),
            ]

            if let nextPageToken {
                queryItems.append(URLQueryItem(name: "nextPageToken", value: nextPageToken))
            }

            let response: SearchResponse = try await get(
                path: "/rest/api/3/search/jql",
                queryItems: queryItems,
            )
            issues.append(contentsOf: response.issues)
            nextPageToken = response.nextPageToken

            if response.isLast == true || nextPageToken == nil {
                break
            }
        } while true

        return issues
    }

    public func comments(for issueKey: String) async throws -> [JiraComment] {
        var comments: [JiraComment] = []
        var startAt = 0

        repeat {
            let response: CommentsResponse = try await get(
                path: "/rest/api/3/issue/\(issueKey)/comment",
                queryItems: [
                    URLQueryItem(name: "startAt", value: String(startAt)),
                    URLQueryItem(name: "maxResults", value: "100"),
                    URLQueryItem(name: "orderBy", value: "created"),
                ],
            )

            comments.append(contentsOf: response.comments)

            if response.isLast == true {
                break
            }

            let received = response.comments.count
            let total = response.total ?? comments.count
            if received == 0 || comments.count >= total {
                break
            }

            startAt += response.maxResults ?? received
        } while true

        return comments
    }

    private func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw JiraToolsError("Could not build URL for \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraToolsError("No HTTP response for \(url.absoluteString)")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            throw JiraToolsError("Jira returned HTTP \(httpResponse.statusCode) for \(url.absoluteString): \(body)")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw JiraToolsError("Could not decode Jira response from \(url.absoluteString): \(error)")
        }
    }
}

public func resolveJiraLocation(
    filterURL: URL?,
    jql: String?,
    baseURL: URL?,
) throws -> ResolvedJiraLocation {
    if let jql {
        guard let resolvedBaseURL = baseURL ?? filterURL.flatMap(jiraBaseURL(from:)) else {
            throw JiraToolsError("When using --jql, provide --base-url or a full --filter-url so the Jira site can be detected.")
        }
        return ResolvedJiraLocation(baseURL: resolvedBaseURL, jql: jql)
    }

    guard let filterURL else {
        throw JiraToolsError("Provide --filter-url or --jql with --base-url.")
    }

    guard let components = URLComponents(url: filterURL, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems else {
        throw JiraToolsError("Filter URL has no query string: \(filterURL.absoluteString)")
    }

    guard let resolvedBaseURL = jiraBaseURL(from: filterURL) else {
        throw JiraToolsError("Could not infer Jira base URL from \(filterURL.absoluteString)")
    }

    if let jql = queryItems.first(where: { $0.name == "jql" })?.value, !jql.isEmpty {
        return ResolvedJiraLocation(baseURL: resolvedBaseURL, jql: jql)
    }

    if let filterID = queryItems.first(where: { $0.name == "filter" })?.value, !filterID.isEmpty {
        return ResolvedJiraLocation(baseURL: resolvedBaseURL, jql: "filter = \(filterID)")
    }

    throw JiraToolsError("Filter URL must include either a filter=ID or jql=... query parameter.")
}

public func jiraBaseURL(from url: URL) -> URL? {
    guard let scheme = url.scheme, let host = url.host else {
        return nil
    }

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = url.port
    return components.url
}

public func jiraURL(from input: String) -> URL? {
    let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedInput.isEmpty else {
        return nil
    }

    let urlString = trimmedInput.contains("://") ? trimmedInput : "https://\(trimmedInput)"
    guard let url = URL(string: urlString),
          let scheme = url.scheme,
          let host = url.host,
          !scheme.isEmpty,
          !host.isEmpty else {
        return nil
    }

    return url
}
