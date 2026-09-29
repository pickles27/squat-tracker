import Foundation
import Testing
@testable import SquatsCore

@MainActor
struct ExportTests {
    func storeWithHistory() -> (WorkoutStore, Program) {
        let store = makeStore()
        let program = store.createProgram(makeProgram(options: .init(includeWarmups: false)), now: monday)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.startWorkout(first.id, now: monday)
        for set in store.workout(first.id)!.sets { store.toggleSet(workoutID: first.id, setID: set.id, now: monday) }
        let amrap = store.workout(first.id)!.sets.first { $0.liftID == "squat" && $0.isAMRAP }!
        store.updateSet(workoutID: first.id, setID: amrap.id) { $0.reps = 7 }
        let accessory = store.addAccessory(to: first.id, named: "Lunges, walking")!
        let setID = store.workout(first.id)!.accessories[0].sets[0].id
        store.toggleAccessorySet(workoutID: first.id, accessoryID: accessory, setID: setID, now: monday)
        store.setNotes("Felt \"great\"", workoutID: first.id)
        store.completeWorkout(first.id, now: monday)
        return (store, program)
    }

    func document(_ store: WorkoutStore, includePlanned: Bool = false) -> ExportDocument {
        Exporter.makeDocument(programs: store.programs, workouts: store.workouts, account: nil,
                              options: ExportOptions(includePlanned: includePlanned), exportedAt: monday,
                              calendar: TestCalendar.calendar)
    }

    @Test func csvHasOneRowPerSet() {
        let (store, _) = storeWithHistory()
        let csv = Exporter.csv(document(store), timeZone: TestCalendar.calendar.timeZone)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.first == Exporter.csvColumns.joined(separator: ","))
        #expect(lines.count == 1 + 16 + 3) // header + 2 lifts × (3 main + 5 FSL) + 3 accessory sets
        #expect(lines[1].hasPrefix("5/3/1 for Beginners,"))
        #expect(lines[3].contains(",Squat,100,main,3,85,5,true,85,85,7,true,kg,\"Felt \"\"great\"\"\""))
        #expect(lines[17].contains(",\"Lunges, walking\",,accessory,1,,,false,,0,10,true,kg,"))
        #expect(lines[1].contains(",2026-09-28,completed,2026-09-28T10:00:00Z,"))
    }

    @Test func plannedWorkoutsAreOptional() {
        let (store, _) = storeWithHistory()
        #expect(document(store).programs[0].workouts.count == 1)
        let with = document(store, includePlanned: true)
        #expect(with.programs[0].workouts.count == 37)
        let planned = with.programs[0].workouts[1]
        #expect(planned.status == "planned")
        #expect(planned.sets.filter { $0.type == "main" }.map(\.targetWeight) == [90, 105, 120])
        #expect(planned.sets.allSatisfy { $0.weight == nil && $0.reps == nil })
    }

    @Test func jsonRoundTrips() throws {
        let (store, program) = storeWithHistory()
        let account = UserAccount(provider: .google, subject: "123", email: "a@b.c", name: "A B")
        let document = Exporter.makeDocument(programs: store.programs, workouts: store.workouts, account: account,
                                             options: ExportOptions(), exportedAt: monday, calendar: TestCalendar.calendar)
        let data = try Exporter.json(document)
        #expect(String(decoding: data, as: UTF8.self).contains("\"exportedAt\" : \"2026-09-28T10:00:00Z\""))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportDocument.self, from: data)
        let entry = try #require(decoded.programs.first)
        #expect(entry.id == program.id)
        #expect(entry.workoutDays == ["Monday", "Wednesday", "Friday"])
        #expect(entry.lifts.map(\.name) == ["Squat", "Bench Press", "Deadlift"])
        #expect(entry.workouts.first?.trainingMaxes == ["Squat": 100, "Bench Press": 60])
        #expect(entry.workouts.first?.accessories.first?.name == "Lunges, walking")
        #expect(decoded.account?.email == "a@b.c")
    }

    @Test func writesFile() throws {
        let (store, _) = storeWithHistory()
        let url = try Exporter.writeFile(document(store), format: .csv, calendar: TestCalendar.calendar)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent == "squats-export-2026-09-28.csv")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@MainActor
struct SyncMergeTests {
    let early = TestCalendar.date("2026-09-28", hour: 8)
    let late = TestCalendar.date("2026-09-28", hour: 12)

    @Test func newestRecordWins() {
        let program = makeProgram()
        var older = program
        older.name = "Old"
        older.updatedAt = early
        var newer = program
        newer.name = "New"
        newer.updatedAt = late
        let merged = SyncMerge.merge(AppData(programs: [older]), AppData(programs: [newer]))
        #expect(merged.programs.map(\.name) == ["New"])
        #expect(SyncMerge.merge(AppData(programs: [newer]), AppData(programs: [older])).programs.map(\.name) == ["New"])
    }

    @Test func deletionsWinUnlessEditedLater() {
        var program = makeProgram()
        program.updatedAt = early
        let deleted = AppData(deletions: [Tombstone(id: program.id, deletedAt: TestCalendar.date("2026-09-28", hour: 10))])
        #expect(SyncMerge.merge(AppData(programs: [program]), deleted).programs.isEmpty)
        program.updatedAt = late
        #expect(SyncMerge.merge(AppData(programs: [program]), deleted).programs.count == 1)
    }

    @Test func orphanedWorkoutsAreDropped() {
        let workout = Workout(programID: UUID(), sessionIndex: 0, scheduledDate: early)
        #expect(SyncMerge.merge(AppData(workouts: [workout]), AppData()).workouts.isEmpty)
    }

    @Test func twoDevicesConverge() {
        let phone = makeStore(now: early)
        let program = phone.createProgram(makeProgram(), now: monday)
        let tablet = makeStore(now: early)
        tablet.replaceAll(with: phone.snapshot(), now: monday)
        #expect(tablet.workouts == phone.workouts)

        // Phone logs a workout, tablet renames the program later.
        phone.clock = { TestCalendar.date("2026-09-28", hour: 11) }
        _ = completeNext(phone, programID: program.id, now: monday, amrapReps: 7)
        tablet.clock = { late }
        tablet.updateProgram(program.id) { $0.name = "Renamed" }

        let merged = SyncMerge.merge(phone.snapshot(), tablet.snapshot())
        phone.replaceAll(with: merged, now: monday)
        tablet.replaceAll(with: merged, now: monday)
        #expect(phone.program(program.id)?.name == "Renamed")
        #expect(tablet.history(programID: program.id).count == 1)
        #expect(phone.workouts == tablet.workouts)
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

    @Test func authorizationURLRequestsDriveAppData() {
        let url = config.authorizationURL(state: "s1", codeChallenge: "c1", nonce: "n1")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "accounts.google.com")
        #expect(query["response_type"] == "code")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["scope"] == "openid email profile https://www.googleapis.com/auth/drive.appdata")
        #expect(query["redirect_uri"] == config.redirectURI)
    }

    @Test func callbackParsing() throws {
        let ok = URL(string: "com.googleusercontent.apps.1234-abcd:/oauthredirect?state=s1&code=4/abc")!
        #expect(try config.authorizationCode(from: ok, expectedState: "s1") == "4/abc")
        #expect(throws: OAuthError.stateMismatch) { try config.authorizationCode(from: ok, expectedState: "other") }
        let denied = URL(string: "com.googleusercontent.apps.1234-abcd:/oauthredirect?error=access_denied&state=s1")!
        #expect(throws: OAuthError.provider("access_denied")) { try config.authorizationCode(from: denied, expectedState: "s1") }
    }

    @Test func tokenRequestsAreFormEncoded() {
        let exchange = String(decoding: config.tokenRequest(code: "4/abc", codeVerifier: "v").httpBody!, as: UTF8.self)
        #expect(exchange.contains("code=4%2Fabc"))
        #expect(exchange.contains("grant_type=authorization_code"))
        #expect(exchange.contains("redirect_uri=com.googleusercontent.apps.1234-abcd%3A%2Foauthredirect"))
        let refresh = String(decoding: config.refreshRequest(refreshToken: "1//r").httpBody!, as: UTF8.self)
        #expect(refresh == "client_id=1234-abcd.apps.googleusercontent.com&grant_type=refresh_token&refresh_token=1%2F%2Fr")
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
