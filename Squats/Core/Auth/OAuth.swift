import CryptoKit
import Foundation

enum AuthProvider: String, Codable, Sendable {
    case google
    /// On-device account for development builds.
    case local

    var displayName: String {
        switch self {
        case .google: "Google"
        case .local: "This device"
        }
    }
}

struct UserAccount: Codable, Hashable, Identifiable, Sendable {
    var provider: AuthProvider
    /// Stable subject ID from the identity provider.
    var subject: String
    var email: String?
    var name: String?
    var pictureURL: URL?

    var id: String { "\(provider.rawValue):\(subject)" }
    var displayName: String { name ?? email ?? "Athlete" }
    var firstName: String { displayName.split(separator: " ").first.map(String.init) ?? displayName }

    /// Filesystem-safe folder name so every account gets its own data file.
    var storageKey: String {
        SHA256.hash(data: Data(id.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    static func random(byteCount: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return encode(Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }
}

/// Proof Key for Code Exchange (RFC 7636), required for public clients like mobile apps.
struct PKCE: Sendable {
    let verifier: String
    let challenge: String

    init(verifier: String = Base64URL.random()) {
        self.verifier = verifier
        self.challenge = Self.challenge(for: verifier)
    }

    static func challenge(for verifier: String) -> String {
        Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

enum OAuthError: LocalizedError, Equatable {
    case notConfigured
    case stateMismatch
    case missingAuthorizationCode
    case provider(String)
    case tokenExchangeFailed(status: Int, message: String)
    case missingIDToken
    case invalidIDToken(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google Sign-In isn't set up yet. Add your OAuth client ID in AppConfig.swift."
        case .stateMismatch: "The sign-in response didn't match the request. Please try again."
        case .missingAuthorizationCode: "Google didn't return an authorization code."
        case .provider(let message): "Google sign-in failed: \(message)"
        case .tokenExchangeFailed(let status, let message): "Couldn't finish signing in (\(status)): \(message)"
        case .missingIDToken: "Google didn't return an identity token."
        case .invalidIDToken(let reason): "The identity token was invalid: \(reason)"
        }
    }
}

/// Authorization-code + PKCE flow for a Google "iOS" OAuth client (no client secret).
struct GoogleOAuthConfiguration: Sendable {
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let driveAppDataScope = "https://www.googleapis.com/auth/drive.appdata"
    /// Identity plus the hidden per-app Drive folder used for backup and sync (a non-sensitive scope).
    static let scopes = ["openid", "email", "profile", driveAppDataScope]

    let clientID: String

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    var callbackScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    var redirectURI: String { "\(callbackScheme):/oauthredirect" }

    var isValid: Bool {
        clientID.hasSuffix(".apps.googleusercontent.com") && !clientID.hasPrefix("YOUR_")
    }

    func authorizationURL(state: String, codeChallenge: String, nonce: String) -> URL {
        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components.url!
    }

    func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw OAuthError.provider(error) }
        guard value("state") == expectedState else { throw OAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw OAuthError.missingAuthorizationCode }
        return code
    }

    func tokenRequest(code: String, codeVerifier: String) -> URLRequest {
        formRequest(Self.tokenEndpoint, [
            "client_id": clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ])
    }

    /// Exchanges the stored refresh token for a fresh access token.
    func refreshRequest(refreshToken: String) -> URLRequest {
        formRequest(Self.tokenEndpoint, [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
    }

    func revokeRequest(token: String) -> URLRequest {
        formRequest(Self.revokeEndpoint, ["token": token])
    }

    private func formRequest(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return request
    }
}

struct OAuthTokenResponse: Decodable, Sendable {
    var accessToken: String
    var expiresIn: Int?
    var idToken: String?
    var refreshToken: String?
    var scope: String?
    var tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

struct GoogleIDToken: Decodable, Sendable {
    var iss: String
    var audiences: [String]
    var sub: String
    var email: String?
    var name: String?
    var picture: String?
    var exp: Double
    var nonce: String?

    enum CodingKeys: String, CodingKey {
        case iss, aud, sub, email, name, picture, exp, nonce
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iss = try container.decode(String.self, forKey: .iss)
        if let single = try? container.decode(String.self, forKey: .aud) {
            audiences = [single]
        } else {
            audiences = try container.decode([String].self, forKey: .aud)
        }
        sub = try container.decode(String.self, forKey: .sub)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        picture = try container.decodeIfPresent(String.self, forKey: .picture)
        exp = try container.decode(Double.self, forKey: .exp)
        nonce = try container.decodeIfPresent(String.self, forKey: .nonce)
    }

    /// The token comes straight from Google's token endpoint over TLS, so per OpenID Connect Core §3.1.3.7
    /// checking issuer, audience, expiry and nonce is sufficient (no signature check needed).
    func validate(clientID: String, nonce expectedNonce: String, now: Date = .now) throws {
        guard iss == "https://accounts.google.com" || iss == "accounts.google.com" else {
            throw OAuthError.invalidIDToken("unexpected issuer")
        }
        guard audiences.contains(clientID) else { throw OAuthError.invalidIDToken("wrong audience") }
        guard Date(timeIntervalSince1970: exp) > now.addingTimeInterval(-300) else { throw OAuthError.invalidIDToken("expired") }
        guard nonce == expectedNonce else { throw OAuthError.invalidIDToken("nonce mismatch") }
    }

    var account: UserAccount {
        UserAccount(provider: .google, subject: sub, email: email, name: name, pictureURL: picture.flatMap(URL.init(string:)))
    }
}

enum JWT {
    static func payload<T: Decodable>(of token: String, as type: T.Type) throws -> T {
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let data = Base64URL.decode(String(parts[1])) else {
            throw OAuthError.invalidIDToken("malformed token")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
