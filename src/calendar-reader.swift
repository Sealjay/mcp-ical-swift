import EventKit
import Foundation

let store = EKEventStore()
let args = CommandLine.arguments

func printJSON(_ dict: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: dict)
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

func printJSONArray(_ array: [[String: Any]]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: array)
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

guard args.count >= 2 else {
    printJSON(["error": "Usage: calendar-reader <command> [args...]"])
    exit(1)
}

let command = args[1]

switch command {
case "list-calendars":
    let calendars = store.calendars(for: .event)
    var result: [[String: String]] = []
    for cal in calendars {
        result.append([
            "name": cal.title,
            "uid": cal.calendarIdentifier,
            "type": String(describing: cal.type.rawValue)
        ])
    }
    printJSONArray(result as [[String: Any]])

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
        printJSON(["error": "Invalid start date: \(startStr). Use YYYY-MM-DD"])
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
        if let cal = store.calendars(for: .event).first(where: { $0.title == calName }) {
            cals = [cal]
        } else {
            printJSON(["error": "Calendar not found: \(calName)"])
            exit(1)
        }
    }

    let includeNotes = args.count >= 6 && args[5] == "true"

    let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: cals)
    let events = store.events(matching: predicate)

    var result: [[String: Any]] = []
    let isoFormatter = ISO8601DateFormatter()
    for event in events {
        var dict: [String: Any] = [
            "title": event.title ?? "",
            "start": isoFormatter.string(from: event.startDate),
            "end": isoFormatter.string(from: event.endDate),
            "allDay": event.isAllDay,
            "calendar": event.calendar.title
        ]
        if let uid = event.eventIdentifier { dict["uid"] = uid }
        if let location = event.location { dict["location"] = location }
        if includeNotes, let notes = event.notes { dict["notes"] = notes }
        result.append(dict)
    }
    printJSONArray(result)

case "search":
    guard args.count >= 3 else {
        printJSON(["error": "Usage: calendar-reader search <query> [days-ahead] [calendar-name] [include-notes]"])
        exit(1)
    }
    let query = args[2].lowercased()
    let daysAhead = args.count >= 4 ? (Int(args[3]) ?? 30) : 30

    let start = Calendar.current.startOfDay(for: Date())
    guard let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start) else {
        printJSON(["error": "Failed to calculate end date"])
        exit(1)
    }

    var cals: [EKCalendar]? = nil
    if args.count >= 5 && !args[4].isEmpty {
        let calName = args[4]
        if let cal = store.calendars(for: .event).first(where: { $0.title == calName }) {
            cals = [cal]
        } else {
            printJSON(["error": "Calendar not found: \(calName)"])
            exit(1)
        }
    }

    let includeNotesInSearch = args.count >= 6 && args[5] == "true"

    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
    let events = store.events(matching: predicate)

    let isoFormatter = ISO8601DateFormatter()
    var result: [[String: Any]] = []
    for event in events {
        let title = (event.title ?? "").lowercased()
        let location = (event.location ?? "").lowercased()
        let notes = (event.notes ?? "").lowercased()
        if title.contains(query) || location.contains(query) || notes.contains(query) {
            var dict: [String: Any] = [
                "title": event.title ?? "",
                "start": isoFormatter.string(from: event.startDate),
                "end": isoFormatter.string(from: event.endDate),
                "calendar": event.calendar.title
            ]
            if let uid = event.eventIdentifier { dict["uid"] = uid }
            if let location = event.location { dict["location"] = location }
            if includeNotesInSearch, let notes = event.notes { dict["notes"] = notes }
            result.append(dict)
        }
    }
    printJSONArray(result)

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
        printJSON(["error": "Invalid start date: \(args[3])"])
        exit(1)
    }
    guard let endDate = parseDate(args[4]) else {
        printJSON(["error": "Invalid end date: \(args[4])"])
        exit(1)
    }

    let event = EKEvent(eventStore: store)
    event.title = title
    event.startDate = startDate
    event.endDate = endDate

    if args.count > 5 && !args[5].isEmpty {
        let calName = args[5]
        if let cal = store.calendars(for: .event).first(where: { $0.title == calName }) {
            event.calendar = cal
        } else {
            printJSON(["error": "Calendar not found: \(calName)"])
            exit(1)
        }
    } else {
        event.calendar = store.defaultCalendarForNewEvents
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
        printJSON(["error": "Event not found: \(eventId)"])
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
        printJSON(["error": "Usage: calendar-reader get-event <event-id>"])
        exit(1)
    }
    let eventId = args[2]
    guard let event = store.event(withIdentifier: eventId) else {
        printJSON(["error": "Event not found: \(eventId)"])
        exit(1)
    }
    let isoFormatter = ISO8601DateFormatter()
    var dict: [String: Any] = [
        "uid": event.eventIdentifier ?? "",
        "title": event.title ?? "",
        "start": isoFormatter.string(from: event.startDate),
        "end": isoFormatter.string(from: event.endDate),
        "allDay": event.isAllDay,
        "calendar": event.calendar.title
    ]
    if let location = event.location { dict["location"] = location }
    if let notes = event.notes { dict["notes"] = notes }
    if let url = event.url { dict["url"] = url.absoluteString }
    if event.hasRecurrenceRules, let _ = event.recurrenceRules {
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
        printJSON(["error": "Event not found: \(eventId)"])
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
    printJSON(["error": "Unknown command: \(command). Use list-calendars, list-events, search, create-event, update-event, get-event, delete-event"])
    exit(1)
}
