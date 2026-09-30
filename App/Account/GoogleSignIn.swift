import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// "Sign in with Google" without Google's SDK: the system sign-in sheet
/// opens Google's page, PKCE protects the code, and only Google's signed ID
/// token goes to Ma's server, which checks it against Google's keys.
///
/// Needs the iOS OAuth client id in Info.plist under `MaGoogleClientID`
/// (set through the GOOGLE_IOS_CLIENT_ID build setting). Without it the
/// button stays hidden.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MaGoogleClientID") as? String,
              value.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return value
    }

    static var isAvailable: Bool { clientID != nil }

    /// "123-abc.apps.googleusercontent.com" becomes
    /// "com.googleusercontent.apps.123-abc", Google's redirect scheme for iOS.
    private static func redirectScheme(_ clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    private var session: ASWebAuthenticationSession?

    /// Returns Google's ID token, or throws `AccountError.cancelled` when the
    /// person closes the sheet.
    func idToken() async throws -> String {
        guard let clientID = Self.clientID else { throw AccountError.invalid("Google sign-in is not set up") }
        let scheme: String = Self.redirectScheme(clientID)
        let redirect = "\(scheme):/oauth2redirect"
        let verifier: String = Self.randomURLSafe(48)
        let challenge: String = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state: String = Self.randomURLSafe(24)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callback: .customScheme(scheme)) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AccountError.cancelled)
                } else {
                    continuation.resume(throwing: AccountError.offline)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        let items: [URLQueryItem] = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw AccountError.invalid(tr("Google did not confirm the sign-in.", "Google hat die Anmeldung nicht bestätigt."))
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        struct TokenResponse: Decodable { var id_token: String? }
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw AccountError.offline
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data).id_token else {
            throw AccountError.invalid(tr("Google did not confirm the sign-in.", "Google hat die Anmeldung nicht bestätigt."))
        }
        return token
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
