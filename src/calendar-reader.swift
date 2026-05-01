import EventKit
import Foundation

let store = EKEventStore()
let args = CommandLine.arguments

guard args.count >= 2 else {
    let encoder = JSONEncoder()
    let error = ["error": "Usage: calendar-reader <command> [args...]"]
    print(String(data: try! encoder.encode(error), encoding: .utf8)!)
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
    let data = try! JSONSerialization.data(withJSONObject: result)
    print(String(data: data, encoding: .utf8)!)

case "list-events":
    guard args.count >= 3 else {
        print("{\"error\": \"Usage: calendar-reader list-events <date> [end-date]\"}")
        exit(1)
    }
    let df = ISO8601DateFormatter()
    df.formatOptions = [.withFullDate]

    let startStr = args[2]
    let endStr = args.count >= 4 ? args[3] : startStr

    guard let startDate = df.date(from: startStr) else {
        print("{\"error\": \"Invalid start date: \(startStr). Use YYYY-MM-DD\"}")
        exit(1)
    }

    var endDate = df.date(from: endStr) ?? startDate
    endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate)!

    let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
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
        if let notes = event.notes { dict["notes"] = notes }
        result.append(dict)
    }
    let data = try! JSONSerialization.data(withJSONObject: result)
    print(String(data: data, encoding: .utf8)!)

case "search":
    guard args.count >= 3 else {
        print("{\"error\": \"Usage: calendar-reader search <query> [days-ahead]\"}")
        exit(1)
    }
    let query = args[2].lowercased()
    let daysAhead = args.count >= 4 ? (Int(args[3]) ?? 30) : 30

    let start = Calendar.current.startOfDay(for: Date())
    let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start)!
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
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
            result.append(dict)
        }
    }
    let data = try! JSONSerialization.data(withJSONObject: result)
    print(String(data: data, encoding: .utf8)!)

case "create-event":
    guard args.count >= 5 else {
        print("{\"error\": \"Usage: calendar-reader create-event <title> <start-iso> <end-iso> [calendar-name] [location] [notes] [all-day]\"}")
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
        print("{\"error\": \"Invalid start date: \(args[3])\"}")
        exit(1)
    }
    guard let endDate = parseDate(args[4]) else {
        print("{\"error\": \"Invalid end date: \(args[4])\"}")
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
            print("{\"error\": \"Calendar not found: \(calName)\"}")
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
        let result: [String: Any] = ["uid": event.eventIdentifier ?? "", "title": title, "status": "created"]
        let data = try! JSONSerialization.data(withJSONObject: result)
        print(String(data: data, encoding: .utf8)!)
    } catch {
        print("{\"error\": \"Failed to create event: \(error.localizedDescription)\"}")
        exit(1)
    }

case "update-event":
    guard args.count >= 3 else {
        print("{\"error\": \"Usage: calendar-reader update-event <event-id> [title] [start-iso] [end-iso] [location] [notes]\"}")
        exit(1)
    }
    let eventId = args[2]
    guard let event = store.event(withIdentifier: eventId) else {
        print("{\"error\": \"Event not found: \(eventId)\"}")
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
        let result: [String: Any] = ["uid": event.eventIdentifier ?? "", "title": event.title ?? "", "status": "updated"]
        let data = try! JSONSerialization.data(withJSONObject: result)
        print(String(data: data, encoding: .utf8)!)
    } catch {
        print("{\"error\": \"Failed to update event: \(error.localizedDescription)\"}")
        exit(1)
    }

case "get-event":
    guard args.count >= 3 else {
        print("{\"error\": \"Usage: calendar-reader get-event <event-id>\"}")
        exit(1)
    }
    let eventId = args[2]
    guard let event = store.event(withIdentifier: eventId) else {
        print("{\"error\": \"Event not found: \(eventId)\"}")
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
    if event.hasRecurrenceRules, let rules = event.recurrenceRules {
        dict["hasRecurrence"] = true
    }
    let data = try! JSONSerialization.data(withJSONObject: dict)
    print(String(data: data, encoding: .utf8)!)

case "delete-event":
    guard args.count >= 3 else {
        print("{\"error\": \"Usage: calendar-reader delete-event <event-id>\"}")
        exit(1)
    }
    let eventId = args[2]
    guard let event = store.event(withIdentifier: eventId) else {
        print("{\"error\": \"Event not found: \(eventId)\"}")
        exit(1)
    }
    do {
        try store.remove(event, span: .thisEvent)
        print("{\"status\": \"deleted\", \"uid\": \"\(eventId)\"}")
    } catch {
        print("{\"error\": \"Failed to delete event: \(error.localizedDescription)\"}")
        exit(1)
    }

default:
    print("{\"error\": \"Unknown command: \(command). Use list-calendars, list-events, search, create-event, update-event, get-event, delete-event\"}")
    exit(1)
}
