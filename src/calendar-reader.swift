import EventKit
import Foundation
import MachO

// --- TCC responsible-process disclaim -------------------------------------------------
// EventKit attributes its access prompt to the *responsible* process: the GUI app at the
// top of the launch chain. Under Cowork that is Claude.app, which ships no calendar
// usage-description string, so macOS silently denies and never shows a prompt. We break
// that inheritance — on first entry we re-spawn ourselves with the private
// `responsibility_spawnattrs_setdisclaim` attribute (as used by LLDB and Qt Creator) set,
// making the child its own responsible process. macOS then reads *our* embedded
// NSCalendarsFullAccessUsageDescription and prompts as "mcp-ical-swift", whichever host
// launched us — so one grant works in Cowork, Claude Code and the terminal alike.
// ponytail: private libSystem symbol, dlsym'd and absence-tolerant; if Apple ever drops
// it we fall through to the legacy inline path (host-attributed, exactly as before).
func executablePath() -> String {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buf = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buf, &size) == 0 else { return CommandLine.arguments[0] }
    return String(cString: buf)
}

func disclaimAndReexecIfNeeded() {
    // The re-spawned child carries this marker and runs the real work inline.
    if ProcessInfo.processInfo.environment["ICAL_DISCLAIMED"] == "1" { return }

    let handle = dlopen(nil, RTLD_LAZY)
    guard let sym = dlsym(handle, "responsibility_spawnattrs_setdisclaim") else { return }
    typealias DisclaimFn = @convention(c) (posix_spawnattr_t?, Int32) -> Int32
    let setDisclaim = unsafeBitCast(sym, to: DisclaimFn.self)

    var attr: posix_spawnattr_t?
    guard posix_spawnattr_init(&attr) == 0 else { return }
    defer { posix_spawnattr_destroy(&attr) }
    guard setDisclaim(attr, 1) == 0 else { return }

    var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) }
    argv.append(nil)
    var env = ProcessInfo.processInfo.environment
    env["ICAL_DISCLAIMED"] = "1"
    var envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") }
    envp.append(nil)

    var pid: pid_t = 0
    let rc = posix_spawn(&pid, executablePath(), nil, &attr, argv, envp)
    for p in argv where p != nil { free(p) }
    for p in envp where p != nil { free(p) }
    guard rc == 0 else { return }  // spawn failed → fall through to the legacy inline path

    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    if (status & 0x7f) == 0 { exit((status >> 8) & 0xff) }  // WIFEXITED → propagate exit code
    exit(128 + (status & 0x7f))                             // killed by signal
}

disclaimAndReexecIfNeeded()

let store = EKEventStore()
let args = CommandLine.arguments
let outputFormatter = ISO8601DateFormatter()

func printJSON(_ value: Any) {
    do {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let str = String(data: data, encoding: .utf8) else {
            fputs("{\"error\":\"Failed to encode JSON as UTF-8\"}\n", stderr)
            exit(1)
        }
        print(str)
    } catch {
        fputs("{\"error\":\"JSON serialisation failed: \(error.localizedDescription)\"}\n", stderr)
        exit(1)
    }
}

func findCalendar(named name: String) -> EKCalendar? {
    store.calendars(for: .event).first(where: { $0.title == name })
}

// EventKit grants are attributed to the host process (Terminal, iTerm, Cowork...).
// A host that never requests access is never listed in System Settings > Privacy &
// Security > Calendars, so it cannot be granted there by hand — reads come back empty
// and writes fail. Requesting here is what makes the prompt (and the entry) appear.
func requireCalendarAccess() {
    let semaphore = DispatchSemaphore(value: 0)
    var granted = false
    var failure: Error?
    store.requestFullAccessToEvents { ok, error in
        granted = ok
        failure = error
        semaphore.signal()
    }
    semaphore.wait()

    guard granted else {
        let detail = failure.map { ": \($0.localizedDescription)" } ?? ""
        fputs(
            "{\"error\":\"Calendar access denied for the host app\(detail). Approve the prompt, or enable this app under System Settings > Privacy & Security > Calendars.\"}\n",
            stderr)
        exit(1)
    }
}

guard args.count >= 2 else {
    printJSON(["error": "Usage: calendar-reader <command> [args...]"])
    exit(1)
}

let command = args[1]

requireCalendarAccess()

switch command {
case "list-calendars":
    let calendars = store.calendars(for: .event)
    var result: [[String: String]] = []
    for cal in calendars {
        result.append([
            "name": cal.title,
            "uid": cal.calendarIdentifier,
            "type": String(cal.type.rawValue)
        ])
    }
    printJSON(result)

case "list-events":
    guard args.count >= 3 else {
        printJSON(["error": "Usage: calendar-reader list-events <date> [end-date] [calendar-name] [include-notes]"])
        exit(1)
    }
    let df = ISO8601DateFormatter()
    df.formatOptions = [.withFullDate]

    let startStr = args[2]
    let endStr = args.count >= 4 ? args[3] : startStr

    guard let startDate = df.date(from: startStr) else {
        printJSON(["error": "Invalid start date. Use YYYY-MM-DD format"])
        exit(1)
    }

    var endDate = df.date(from: endStr) ?? startDate
    guard let endDatePlusOne = Calendar.current.date(byAdding: .day, value: 1, to: endDate) else {
        printJSON(["error": "Failed to calculate end date"])
        exit(1)
    }
    endDate = endDatePlusOne

    // Cap date range at 90 days
    let daysBetween = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    if daysBetween > 90 {
        printJSON(["error": "Date range exceeds 90-day maximum. Requested \(daysBetween) days."])
        exit(1)
    }

    var cals: [EKCalendar]? = nil
    if args.count >= 5 && !args[4].isEmpty {
        let calName = args[4]
        if let cal = findCalendar(named: calName) {
            cals = [cal]
        } else {
            printJSON(["error": "Calendar not found"])
            exit(1)
        }
    }

    let includeNotes = args.count >= 6 && args[5] == "true"

    let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: cals)
    let events = store.events(matching: predicate)

    var result: [[String: Any]] = []
    for event in events {
        var dict: [String: Any] = [
            "title": event.title ?? "",
            "start": outputFormatter.string(from: event.startDate),
            "end": outputFormatter.string(from: event.endDate),
            "allDay": event.isAllDay,
            "calendar": event.calendar?.title ?? "Unknown"
        ]
        if let uid = event.eventIdentifier { dict["uid"] = uid }
        if let location = event.location { dict["location"] = location }
        if includeNotes, let notes = event.notes { dict["notes"] = notes }
        result.append(dict)
    }
    printJSON(result)

case "search":
    guard args.count >= 3 else {
        printJSON(["error": "Usage: calendar-reader search <query> [days-ahead] [calendar-name] [include-notes]"])
        exit(1)
    }
    let query = args[2].lowercased()
    let rawDaysAhead = args.count >= 4 ? (Int(args[3]) ?? 30) : 30
    guard rawDaysAhead >= 1 && rawDaysAhead <= 365 else {
        printJSON(["error": "days-ahead must be between 1 and 365"])
        exit(1)
    }
    let daysAhead = rawDaysAhead

    let start = Calendar.current.startOfDay(for: Date())
    guard let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start) else {
        printJSON(["error": "Failed to calculate end date"])
        exit(1)
    }

    var cals: [EKCalendar]? = nil
    if args.count >= 5 && !args[4].isEmpty {
        let calName = args[4]
        if let cal = findCalendar(named: calName) {
            cals = [cal]
        } else {
            printJSON(["error": "Calendar not found"])
            exit(1)
        }
    }

    let includeNotesInSearch = args.count >= 6 && args[5] == "true"

    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
    let events = store.events(matching: predicate)

    var result: [[String: Any]] = []
    for event in events {
        let title = (event.title ?? "").lowercased()
        let location = (event.location ?? "").lowercased()
        let notes = (event.notes ?? "").lowercased()
        if title.contains(query) || location.contains(query) || notes.contains(query) {
            var dict: [String: Any] = [
                "title": event.title ?? "",
                "start": outputFormatter.string(from: event.startDate),
                "end": outputFormatter.string(from: event.endDate),
                "calendar": event.calendar?.title ?? "Unknown"
            ]
            if let uid = event.eventIdentifier { dict["uid"] = uid }
            if let location = event.location { dict["location"] = location }
            if includeNotesInSearch, let notes = event.notes { dict["notes"] = notes }
            result.append(dict)
        }
    }
    printJSON(result)

case "create-event":
    guard args.count >= 5 else {
        printJSON(["error": "Usage: calendar-reader create-event <title> <start-iso> <end-iso> [calendar-name] [location] [notes] [all-day]"])
        exit(1)
    }
    let title = args[2]
    let isoF = ISO8601DateFormatter()
    isoF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoF2 = ISO8601DateFormatter()
    isoF2.formatOptions = [.withInternetDateTime]
    let isoF3 = ISO8601DateFormatter()
    isoF3.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

    func parseDate(_ s: String) -> Date? {
        return isoF.date(from: s) ?? isoF2.date(from: s) ?? isoF3.date(from: s)
    }

    guard let startDate = parseDate(args[3]) else {
        printJSON(["error": "Invalid start date. Use ISO 8601 format"])
        exit(1)
    }
    guard let endDate = parseDate(args[4]) else {
        printJSON(["error": "Invalid end date. Use ISO 8601 format"])
        exit(1)
    }

    let event = EKEvent(eventStore: store)
    event.title = title
    event.startDate = startDate
    event.endDate = endDate

    if args.count > 5 && !args[5].isEmpty {
        let calName = args[5]
        if let cal = findCalendar(named: calName) {
            event.calendar = cal
        } else {
            printJSON(["error": "Calendar not found"])
            exit(1)
        }
    } else {
        guard let defaultCal = store.defaultCalendarForNewEvents else {
            printJSON(["error": "No default calendar is configured"])
            exit(1)
        }
        event.calendar = defaultCal
    }

    if args.count > 6 && !args[6].isEmpty { event.location = args[6] }
    if args.count > 7 && !args[7].isEmpty { event.notes = args[7] }
    if args.count > 8 { event.isAllDay = args[8] == "true" }

    do {
        try store.save(event, span: .thisEvent)
        printJSON(["uid": event.eventIdentifier ?? "", "title": title, "status": "created"])
    } catch {
        printJSON(["error": "Failed to create event: \(error.localizedDescription)"])
        exit(1)
    }

case "update-event":
    guard args.count >= 3 else {
        printJSON(["error": "Usage: calendar-reader update-event <event-id> [title] [start-iso] [end-iso] [location] [notes]"])
        exit(1)
    }
    let eventId = args[2]
    guard let event = store.event(withIdentifier: eventId) else {
        printJSON(["error": "Event not found"])
        exit(1)
    }

    let isoF = ISO8601DateFormatter()
    isoF.formatOptions = [.withInternetDateTime]

    if args.count > 3 && !args[3].isEmpty { event.title = args[3] }
    if args.count > 4 && !args[4].isEmpty { if let d = isoF.date(from: args[4]) { event.startDate = d } }
    if args.count > 5 && !args[5].isEmpty { if let d = isoF.date(from: args[5]) { event.endDate = d } }
    if args.count > 6 && !args[6].isEmpty { event.location = args[6] }
    if args.count > 7 && !args[7].isEmpty { event.notes = args[7] }

    do {
        try store.save(event, span: .thisEvent)
        printJSON(["uid": event.eventIdentifier ?? "", "title": event.title ?? "", "status": "updated"])
    } catch {
        printJSON(["error": "Failed to update event: \(error.localizedDescription)"])
        exit(1)
    }

case "get-event":
    guard args.count >= 3 else {
        printJSON(["error": "Usage: calendar-reader get-event <event-id> [include-notes]"])
        exit(1)
    }
    let eventId = args[2]
    guard let event = store.event(withIdentifier: eventId) else {
        printJSON(["error": "Event not found"])
        exit(1)
    }
    let includeNotes = args.count >= 4 && args[3] == "true"
    var dict: [String: Any] = [
        "uid": event.eventIdentifier ?? "",
        "title": event.title ?? "",
        "start": outputFormatter.string(from: event.startDate),
        "end": outputFormatter.string(from: event.endDate),
        "allDay": event.isAllDay,
        "calendar": event.calendar?.title ?? "Unknown"
    ]
    if let location = event.location { dict["location"] = location }
    if includeNotes, let notes = event.notes { dict["notes"] = notes }
    if let url = event.url { dict["url"] = url.absoluteString }
    if event.hasRecurrenceRules {
        dict["hasRecurrence"] = true
    }
    printJSON(dict)

case "delete-event":
    guard args.count >= 3 else {
        printJSON(["error": "Usage: calendar-reader delete-event <event-id>"])
        exit(1)
    }
    let eventId = args[2]
    guard let event = store.event(withIdentifier: eventId) else {
        printJSON(["error": "Event not found"])
        exit(1)
    }
    do {
        try store.remove(event, span: .thisEvent)
        printJSON(["status": "deleted", "uid": eventId])
    } catch {
        printJSON(["error": "Failed to delete event: \(error.localizedDescription)"])
        exit(1)
    }

default:
    printJSON(["error": "Unknown command. Use list-calendars, list-events, search, create-event, update-event, get-event, delete-event"])
    exit(1)
}
