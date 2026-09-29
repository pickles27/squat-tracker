import Foundation
import Testing
@testable import SquatsCore

@MainActor
struct ExportTests {
    let now = TestCalendar.date("2026-09-28", hour: 10)

    func storeWithHistory() -> (WorkoutStore, Program) {
        let store = makeStore()
        let program = store.createProgram(makeProgram(warmups: false), now: now)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.startWorkout(first.id, now: now)
        for set in store.workout(first.id)!.sets { store.toggleSet(workoutID: first.id, setID: set.id, now: now) }
        let accessory = store.addAccessory(to: first.id, named: "Lunges, walking")!
        let setID = store.workout(first.id)!.accessories[0].sets[0].id
        store.toggleAccessorySet(workoutID: first.id, accessoryID: accessory, setID: setID, now: now)
        store.setNotes("Felt \"great\"", workoutID: first.id)
        store.completeWorkout(first.id, now: now)
        return (store, program)
    }

    @Test func csvHasOneRowPerSet() {
        let (store, _) = storeWithHistory()
        let document = Exporter.makeDocument(programs: store.programs, workouts: store.workouts, account: nil,
                                             options: ExportOptions(), exportedAt: now, calendar: TestCalendar.calendar)
        let csv = Exporter.csv(document, timeZone: TestCalendar.calendar.timeZone)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.first == Exporter.csvColumns.joined(separator: ","))
        #expect(lines.count == 1 + 3 + 3) // header + 3 main sets + 3 accessory sets
        #expect(lines[1].hasPrefix("5/3/1 Squat,"))
        #expect(lines[3].contains(",Squat,main,3,85,5,true,85,85,5,true,kg,\"Felt \"\"great\"\"\""))
        #expect(lines[4].contains(",\"Lunges, walking\",accessory,1,"))
        #expect(lines[1].contains(",2026-09-28,completed,2026-09-28T10:00:00Z,"))
    }

    @Test func plannedWorkoutsAreOptional() {
        let (store, _) = storeWithHistory()
        let without = Exporter.makeDocument(programs: store.programs, workouts: store.workouts, account: nil,
                                            options: ExportOptions(includePlanned: false), calendar: TestCalendar.calendar)
        let with = Exporter.makeDocument(programs: store.programs, workouts: store.workouts, account: nil,
                                         options: ExportOptions(includePlanned: true), calendar: TestCalendar.calendar)
        #expect(without.programs[0].workouts.count == 1)
        #expect(with.programs[0].workouts.count == 37)
        let planned = with.programs[0].workouts[1]
        #expect(planned.status == "planned")
        #expect(planned.sets.map(\.targetWeight) == [65, 75, 85])
        #expect(planned.sets.allSatisfy { $0.weight == nil && $0.reps == nil })
    }

    @Test func jsonRoundTrips() throws {
        let (store, program) = storeWithHistory()
        let account = UserAccount(provider: .google, subject: "123", email: "a@b.c", name: "A B")
        let document = Exporter.makeDocument(programs: store.programs, workouts: store.workouts, account: account,
                                             options: ExportOptions(), exportedAt: now, calendar: TestCalendar.calendar)
        let data = try Exporter.json(document)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"exportedAt\" : \"2026-09-28T10:00:00Z\""))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportDocument.self, from: data)
        #expect(decoded.programs.first?.id == program.id)
        #expect(decoded.programs.first?.workoutDays == ["Monday", "Wednesday", "Friday"])
        #expect(decoded.programs.first?.workouts.first?.accessories.first?.name == "Lunges, walking")
        #expect(decoded.account?.email == "a@b.c")
    }

    @Test func writesFile() throws {
        let (store, _) = storeWithHistory()
        let document = Exporter.makeDocument(programs: store.programs, workouts: store.workouts, account: nil,
                                             options: ExportOptions(), exportedAt: now, calendar: TestCalendar.calendar)
        let url = try Exporter.writeFile(document, format: .csv, calendar: TestCalendar.calendar)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent == "squats-export-2026-09-28.csv")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

struct OAuthTests {
    let config = GoogleOAuthConfiguration(clientID: "1234-abcd.apps.googleusercontent.com")

    @Test func pkceMatchesRFC7636Vector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE().verifier.count >= 43)
    }

    @Test func redirectUsesReversedClientID() {
        #expect(config.callbackScheme == "com.googleusercontent.apps.1234-abcd")
        #expect(config.redirectURI == "com.googleusercontent.apps.1234-abcd:/oauthredirect")
        #expect(config.isValid)
        #expect(!GoogleOAuthConfiguration(clientID: "YOUR_CLIENT_ID.apps.googleusercontent.com").isValid)
    }

    @Test func authorizationURL() {
        let url = config.authorizationURL(state: "s1", codeChallenge: "c1", nonce: "n1")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "accounts.google.com")
        #expect(query["response_type"] == "code")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["scope"] == "openid email profile")
        #expect(query["redirect_uri"] == config.redirectURI)
        #expect(query["state"] == "s1")
    }

    @Test func callbackParsing() throws {
        let ok = URL(string: "com.googleusercontent.apps.1234-abcd:/oauthredirect?state=s1&code=4/abc")!
        #expect(try config.authorizationCode(from: ok, expectedState: "s1") == "4/abc")
        #expect(throws: OAuthError.stateMismatch) { try config.authorizationCode(from: ok, expectedState: "other") }
        let denied = URL(string: "com.googleusercontent.apps.1234-abcd:/oauthredirect?error=access_denied&state=s1")!
        #expect(throws: OAuthError.provider("access_denied")) { try config.authorizationCode(from: denied, expectedState: "s1") }
    }

    @Test func tokenRequestIsFormEncoded() {
        let request = config.tokenRequest(code: "4/abc", codeVerifier: "v")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        #expect(request.httpMethod == "POST")
        #expect(body.contains("code=4%2Fabc"))
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("redirect_uri=com.googleusercontent.apps.1234-abcd%3A%2Foauthredirect"))
    }

    func token(_ claims: [String: Any]) -> String {
        let header = Base64URL.encode(Data(#"{"alg":"RS256"}"#.utf8))
        let payload = Base64URL.encode(try! JSONSerialization.data(withJSONObject: claims))
        return "\(header).\(payload).signature"
    }

    @Test func idTokenValidation() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let good: [String: Any] = [
            "iss": "https://accounts.google.com", "aud": config.clientID, "sub": "42", "email": "me@example.com",
            "name": "Squat Person", "exp": 1_800_003_600, "nonce": "n1",
        ]
        let claims = try JWT.payload(of: token(good), as: GoogleIDToken.self)
        try claims.validate(clientID: config.clientID, nonce: "n1", now: now)
        #expect(claims.account.id == "google:42")
        #expect(claims.account.firstName == "Squat")

        #expect(throws: OAuthError.self) { try claims.validate(clientID: "other", nonce: "n1", now: now) }
        #expect(throws: OAuthError.self) { try claims.validate(clientID: config.clientID, nonce: "n2", now: now) }
        #expect(throws: OAuthError.self) {
            try claims.validate(clientID: config.clientID, nonce: "n1", now: now.addingTimeInterval(7200))
        }
    }

    @Test func storageKeyIsStableAndSafe() {
        let account = UserAccount(provider: .google, subject: "42/../x")
        #expect(account.storageKey == UserAccount(provider: .google, subject: "42/../x").storageKey)
        #expect(account.storageKey.count == 32)
        #expect(account.storageKey.allSatisfy { $0.isHexDigit })
    }
}
