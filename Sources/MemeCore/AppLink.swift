import Foundation

/// How a command hands a choice to the running app and waits for Tim's answer, through `status.json`.
public enum AppLink {
    public static let bundleID = "com.timgailey.MemeLab"
    /// A distributed notification whose object is a verb: "changed", "open-library" or "open-panel".
    public static let command = Notification.Name("com.timgailey.MemeLab.command")

    public static func isAlive(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    /// The running app registered in this status file, if its process is still alive.
    public static func appPID(_ store: StatusStore, alive: (Int32) -> Bool = isAlive) -> Int32? {
        guard let pid = store.load().app?.pid, alive(pid) else { return nil }
        return pid
    }

    public enum Outcome: Equatable, Sendable {
        case answered(PickerResult)
        case timedOut
        /// Someone else replaced or cleared the request.
        case withdrawn
        case appQuit
    }

    /// Posts the request, then polls until the app answers it. Always clears the request and its answer before returning.
    public static func ask(
        _ request: AppRequest, store: StatusStore, timeout: TimeInterval, poll: TimeInterval = 0.2,
        appAlive: () -> Bool, notify: () -> Void = {}
    ) throws -> Outcome {
        try store.update { status in
            status.request = request
            status.answer = nil
            status.waitingForPick = true
        }
        defer { withdraw(request.id, store: store) }
        notify()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = store.load()
            if let answer = status.answer, answer.id == request.id {
                return .answered(PickerResult(chosen: answer.chosen, note: answer.note))
            }
            if status.request?.id != request.id { return .withdrawn }
            if !appAlive() { return .appQuit }
            Thread.sleep(forTimeInterval: poll)
        }
        return .timedOut
    }

    public static func withdraw(_ id: String, store: StatusStore) {
        _ = try? store.update { status in
            if status.request?.id == id { status.request = nil }
            if status.answer?.id == id { status.answer = nil }
            if status.request == nil { status.waitingForPick = false }
        }
    }

    /// The app's side: answers the request if it is still the one waiting.
    @discardableResult
    public static func answer(_ id: String, chosen: [String], note: String, store: StatusStore) throws -> Bool {
        var accepted = false
        try store.update { status in
            guard status.request?.id == id else { return }
            status.answer = AppAnswer(id: id, chosen: chosen, note: note)
            status.request = nil
            status.waitingForPick = false
            accepted = true
        }
        return accepted
    }
}
