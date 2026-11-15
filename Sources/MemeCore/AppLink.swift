import Foundation

public enum AppLink {
    public static let bundleID = "com.timgailey.MemeLab"
    /// A distributed notification whose object is a verb: "changed", "open-library" or "open-panel".
    public static let command = Notification.Name("com.timgailey.MemeLab.command")

    /// A process that has exited but not been reaped still answers kill(pid, 0), so zombies count as gone.
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return true }
        return info.kp_proc.p_stat != SZOMB
    }

    public static func appPID(_ store: StatusStore, alive: (Int32) -> Bool = isAlive) -> Int32? {
        guard let pid = store.load().app?.pid, alive(pid) else { return nil }
        return pid
    }

    public enum Outcome: Equatable, Sendable {
        case answered(PickerResult)
        case timedOut
        case withdrawn
        case appQuit
    }

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
