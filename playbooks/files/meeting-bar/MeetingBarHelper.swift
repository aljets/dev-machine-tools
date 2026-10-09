// Calendar reader and meeting alert for the meeting-bar SwiftBar plugin.
//
//   MeetingBarHelper events <out.json>                 write upcoming events
//   MeetingBarHelper alert <title> <start> <join-url> [<docs b64 json>]
//                                                      show the join dialog
//   MeetingBarHelper pill <text> <bg> <fg>             print a title PNG as base64
//   MeetingBarHelper icon <doc|sheet|slides|drive|join> print a file icon PNG as base64
//
// Lives in its own .app bundle and is launched through `open` so that macOS
// attributes the Calendar permission to this bundle. Run directly from
// SwiftBar, TCC would check SwiftBar's Info.plist, which has no
// NSCalendarsFullAccessUsageDescription, and the request is denied silently.
import AppKit
import EventKit

struct Doc: Codable {
    let title: String
    let url: String
    let kind: String
}

struct Meeting: Codable {
    let id: String
    let title: String
    let start: Int
    let end: Int
    let time: String
    let calendar: String
    let color: String
    let join: String?
    let docs: [Doc]
    let link: String
    let uid: String
}

let lookBehind: TimeInterval = 4 * 3600
let lookAhead: TimeInterval = 36 * 3600
let watchdog: TimeInterval = 15

func joinURL(_ event: EKEvent) -> String? {
    let haystack = [event.url?.absoluteString, event.location, event.notes]
        .compactMap { $0 }
        .joined(separator: "\n")
    let zoom = try! NSRegularExpression(
        pattern: #"https://[A-Za-z0-9.-]*zoom(gov)?\.us/(j|my|w)/[^\s<>"')\]]+"#)
    let meet = try! NSRegularExpression(
        pattern: #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#)
    let range = NSRange(haystack.startIndex..., in: haystack)

    if let m = zoom.firstMatch(in: haystack, range: range),
       let r = Range(m.range, in: haystack) {
        let link = String(haystack[r])
        // zoommtg:// goes straight to the Zoom app instead of leaving a
        // "launching meeting" browser tab behind.
        if let comps = URLComponents(string: link),
           let host = comps.host,
           comps.path.hasPrefix("/j/") {
            let confno = comps.path.dropFirst(3).prefix { $0.isNumber }
            var out = "zoommtg://\(host)/join?action=join&confno=\(confno)"
            if let pwd = comps.queryItems?.first(where: { $0.name == "pwd" })?.value {
                out += "&pwd=\(pwd)"
            }
            return out
        }
        return link
    }
    if let m = meet.firstMatch(in: haystack, range: range),
       let r = Range(m.range, in: haystack) {
        return String(haystack[r])
    }
    return nil
}

func googleFileID(_ url: String) -> String? {
    let id = try! NSRegularExpression(pattern: #"(?:/d/|[?&]id=)([A-Za-z0-9_-]{20,})"#)
    guard let m = id.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
          let r = Range(m.range(at: 1), in: url) else { return nil }
    return String(url[r])
}

func docKind(_ url: String) -> String {
    if url.contains("/spreadsheets/") { return "Sheet" }
    if url.contains("/presentation/") { return "Slides" }
    if url.contains("/document/") { return "Doc" }
    return "Drive file"
}

func iconKind(_ url: String) -> String {
    switch docKind(url) {
    case "Sheet": return "sheet"
    case "Slides": return "slides"
    case "Doc": return "doc"
    default: return "drive"
    }
}

func decodeEntities(_ s: String) -> String {
    [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
        .reduce(s) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
}

func plainText(_ html: String) -> String {
    decodeEntities(html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// A link whose text is just the URL is usually introduced by a label on the
// same or previous line, as in "Agenda: <url>" or "Program Doc - <url>".
func label(before text: Substring) -> String? {
    let lines = String(text.suffix(300))
        .replacingOccurrences(of: #"<br\s*/?>|</(div|p|li|h\d)>"#, with: "\n", options: .regularExpression)
        .components(separatedBy: .newlines)
    guard let last = lines.map(plainText).last(where: { !$0.isEmpty }) else { return nil }
    let trimmed = last.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—|"))
    return trimmed.isEmpty || trimmed.count > 60 || trimmed.contains("http") ? nil : trimmed
}

// Files attached in Google Calendar come through CalDAV as ATTACH properties,
// which EventKit keeps but only exposes through the private `attachments`
// property. Links pasted into the description are picked up from the notes.
// The same file often appears in both, so they are deduped by Drive file id.
func docs(_ event: EKEvent) -> [Doc] {
    var found: [Doc] = []
    var seen: Set<String> = []
    func add(_ title: String, _ url: String) {
        let key = googleFileID(url) ?? url
        guard seen.insert(key).inserted else { return }
        found.append(Doc(title: title, url: url, kind: iconKind(url)))
    }

    let attachments = event.responds(to: NSSelectorFromString("attachments"))
        ? event.value(forKey: "attachments") as? [NSObject] ?? [] : []
    for a in attachments {
        guard a.responds(to: NSSelectorFromString("URLString")),
              let url = a.value(forKey: "URLString") as? String,
              url.hasPrefix("https://") else { continue }
        let name = a.responds(to: NSSelectorFromString("fileName")) ? a.value(forKey: "fileName") as? String : nil
        add(name ?? docKind(url), url)
    }

    let haystack = [event.url?.absoluteString, event.location, event.notes]
        .compactMap { $0 }
        .joined(separator: "\n")
    let range = NSRange(haystack.startIndex..., in: haystack)
    let anchor = try! NSRegularExpression(
        pattern: #"<a\s[^>]*href="(https://(?:docs|drive)\.google\.com/[^"]+)"[^>]*>(.*?)</a>"#,
        options: .dotMatchesLineSeparators)
    for m in anchor.matches(in: haystack, range: range) {
        guard let u = Range(m.range(at: 1), in: haystack),
              let t = Range(m.range(at: 2), in: haystack),
              let whole = Range(m.range, in: haystack) else { continue }
        let url = decodeEntities(String(haystack[u]))
        let text = plainText(String(haystack[t]))
        let title = text.isEmpty || text.hasPrefix("http")
            ? label(before: haystack[..<whole.lowerBound]) ?? "Google \(docKind(url))"
            : text
        add(title, url)
    }
    let bare = try! NSRegularExpression(
        pattern: #"https://(docs|drive)\.google\.com/[^\s<>"')\]]+"#)
    for m in bare.matches(in: haystack, range: range) {
        guard let r = Range(m.range, in: haystack) else { continue }
        let url = decodeEntities(String(haystack[r]))
        add(label(before: haystack[..<r.lowerBound]) ?? "Google \(docKind(url))", url)
    }
    return found
}

// Google's event page takes eid = base64("<event id> <calendar id>"). Over
// CalDAV the iCal UID is "<event id>@google.com", and a single occurrence of a
// recurring series is "<event id>_<UTC start>". An occurrence edited on its own
// arrives as "<event id>@google.com/RID=<original start>", the start given in
// seconds since 2001. Anything else gets the day view. Checked against the
// htmlLink Google itself returns for the same events.
func googleLink(_ event: EKEvent) -> String {
    let base = "https://calendar.google.com/calendar"
    let uid = event.calendarItemExternalIdentifier ?? ""
    let parts = uid.components(separatedBy: "/RID=")
    if parts[0].hasSuffix("@google.com"), event.calendar.title.contains("@") {
        // A series split with "this and following" gets a "_R<split start>"
        // UID suffix that is not part of Google's event id.
        var id = String(parts[0].dropLast("@google.com".count))
            .replacingOccurrences(of: #"_R\d{8}T\d{6}Z?$"#, with: "", options: .regularExpression)
        let utc = DateFormatter()
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        if parts.count > 1, let rid = TimeInterval(parts[1]) {
            id += "_" + utc.string(from: Date(timeIntervalSinceReferenceDate: rid))
        } else if event.hasRecurrenceRules {
            id += "_" + utc.string(from: event.occurrenceDate ?? event.startDate)
        }
        let eid = Data("\(id) \(event.calendar.title)".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "\(base)/event?eid=\(eid)"
    }
    let day = DateFormatter()
    day.dateFormat = "yyyy/M/d"
    return "\(base)/r/day/\(day.string(from: event.startDate))"
}

func hex(_ color: NSColor?) -> String {
    guard let c = color?.usingColorSpace(.sRGB) else { return "#8e8e93" }
    return String(format: "#%02x%02x%02x",
                  Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
}

func declined(_ event: EKEvent) -> Bool {
    event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
}

func writeJSON(_ value: some Encodable, to path: String) {
    let data = try! JSONEncoder().encode(value)
    let tmp = path + ".tmp"
    FileManager.default.createFile(atPath: tmp, contents: data)
    _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: path),
                                               withItemAt: URL(fileURLWithPath: tmp))
}

func writeEvents(to path: String) {
    let store = EKEventStore()
    store.requestFullAccessToEvents { granted, _ in
        guard granted else {
            writeJSON(["error": "denied"], to: path)
            exit(0)
        }
        // Google CalDAV accounts get no push, so macOS only pulls changes on
        // Calendar's refresh schedule. Nudge a sync on every run; it is async,
        // so this run reads the local copy and the next one sees the result.
        store.refreshSourcesIfNecessary()
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-lookBehind),
            end: now.addingTimeInterval(lookAhead),
            calendars: nil)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let meetings = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !declined($0) && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                Meeting(
                    id: e.calendarItemIdentifier,
                    title: e.title ?? "(no title)",
                    start: Int(e.startDate.timeIntervalSince1970),
                    end: Int(e.endDate.timeIntervalSince1970),
                    time: formatter.string(from: e.startDate),
                    calendar: e.calendar.title,
                    color: hex(e.calendar.color),
                    join: joinURL(e),
                    docs: docs(e),
                    link: googleLink(e),
                    uid: e.calendarItemExternalIdentifier ?? "")
            }
        writeJSON(meetings, to: path)
        exit(0)
    }
}

let snooze: TimeInterval = 60
let expiryAfterStart: TimeInterval = 300
let panelWidth: CGFloat = 360
let screenMargin: CGFloat = 12

func relative(_ start: Date) -> String {
    let seconds = start.timeIntervalSinceNow
    if seconds > 0 { return "Starts in \(Int(ceil(seconds / 60))) min" }
    let ago = Int(-seconds / 60)
    return ago == 0 ? "Starting now" : "Started \(ago) min ago"
}

// Accepts key status without activating the app, so the alert takes Return /
// Escape but does not pull focus away from whatever is being typed in.
final class AlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Action: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

// Drawn by hand: system push buttons render grey whenever the app is not
// frontmost and ignore bezelColor on macOS 26, so Join would never be blue.
final class PillButton: NSButton {
    let action_: Action
    let fill: NSColor
    let text: NSColor

    init(_ title: String, fill: NSColor, text: NSColor, bold: Bool = false, run: @escaping () -> Void) {
        action_ = Action(run)
        self.fill = fill
        self.text = text
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        target = action_
        action = #selector(Action.fire)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: text,
            .font: NSFont.systemFont(ofSize: 13, weight: bold ? .semibold : .regular),
        ])
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isHighlighted ? fill.withAlphaComponent(0.7) : fill).cgColor
        }
    }

    override var wantsUpdateLayer: Bool { true }

    func pulse() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0.45
        fade.duration = 0.8
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(fade, forKey: "pulse")
    }
}

// A doc under the alert's subtitle. Opening one leaves the alert up, since the
// meeting still needs joining.
final class DocLink: NSButton {
    let action_: Action
    let label: String

    init(_ doc: Doc) {
        action_ = Action { if let url = URL(string: doc.url) { NSWorkspace.shared.open(url) } }
        label = doc.title
        super.init(frame: .zero)
        isBordered = false
        image = fileIconImage(kind: doc.kind)
        imagePosition = .imageLeading
        imageHugsTitle = true
        setTitle(underlined: false)
        cell?.lineBreakMode = .byTruncatingTail
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        target = action_
        action = #selector(Action.fire)
        toolTip = doc.url
    }

    required init?(coder: NSCoder) { fatalError() }

    // Plain label color reads better on the translucent panel than link blue;
    // the file icon and a hover underline mark it as a link.
    func setTitle(underlined: Bool) {
        attributedTitle = NSAttributedString(string: label, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 12),
            .underlineStyle: underlined ? NSUnderlineStyle.single.rawValue : 0,
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setTitle(underlined: true) }
    override func mouseExited(with event: NSEvent) { setTitle(underlined: false) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

struct AlertActions {
    let dismiss: () -> Void
    let snooze: (() -> Void)?
    let join: (() -> Void)?
}

func makePanel(on screen: NSScreen, title: String, subtitle: NSTextField, docs: [Doc],
               actions: AlertActions) -> (NSPanel, PillButton?) {
    let panel = AlertPanel(
        contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 100),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false)
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true

    let background = NSVisualEffectView()
    background.material = .popover
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 16
    background.layer?.masksToBounds = true
    panel.contentView = background

    let icon = NSImageView(image: NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)!)
    icon.symbolConfiguration = .init(pointSize: 24, weight: .regular)
    icon.contentTintColor = .controlAccentColor

    let heading = NSTextField(labelWithString: title)
    heading.font = .systemFont(ofSize: 14, weight: .semibold)
    heading.lineBreakMode = .byTruncatingTail

    let text = NSStackView(views: [heading, subtitle] + docs.map(DocLink.init))
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 2
    text.setCustomSpacing(8, after: subtitle)
    let header = NSStackView(views: [icon, text])
    header.spacing = 12
    header.alignment = docs.isEmpty ? .centerY : .top

    let secondary = NSColor.labelColor.withAlphaComponent(0.1)
    var buttons: [NSButton] = [
        PillButton("Dismiss", fill: secondary, text: .labelColor, run: actions.dismiss),
    ]
    buttons[0].keyEquivalent = "\u{1b}"
    if let snooze = actions.snooze {
        buttons.append(PillButton("Snooze 1m", fill: secondary, text: .labelColor, run: snooze))
    }
    var joinButton: PillButton?
    if let join = actions.join {
        let button = PillButton("Join", fill: .systemBlue, text: .white, bold: true, run: join)
        button.keyEquivalent = "\r"
        buttons.append(button)
        joinButton = button
    }
    let row = NSStackView(views: [NSView()] + buttons)
    row.spacing = 8

    let content = NSStackView(views: [header, row])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 14
    content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
    content.translatesAutoresizingMaskIntoConstraints = false
    background.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        content.topAnchor.constraint(equalTo: background.topAnchor),
        content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        content.widthAnchor.constraint(equalToConstant: panelWidth),
        row.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32),
        header.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -32),
    ])
    background.layoutSubtreeIfNeeded()
    panel.setContentSize(content.fittingSize)

    let area = screen.visibleFrame
    panel.setFrameTopLeftPoint(NSPoint(x: area.maxX - panel.frame.width - screenMargin,
                                       y: area.maxY - screenMargin))
    return (panel, joinButton)
}

var openPanels: [NSPanel] = []

// One panel per display, since there is no telling which one is being looked
// at. Any button on any of them closes them all.
func showAlert(title: String, start: Int, join: String, docs: [Doc]) {
    let startDate = Date(timeIntervalSince1970: TimeInterval(start))
    let expiresAt = startDate.addingTimeInterval(expiryAfterStart)
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    let subtitleText = { "\(relative(startDate)) · \(formatter.string(from: startDate))" }

    var timers: [Timer] = []
    func close() {
        timers.forEach { $0.invalidate() }
        openPanels.forEach { $0.orderOut(nil) }
        openPanels = []
    }

    let actions = AlertActions(
        dismiss: { close(); exit(0) },
        snooze: Date().addingTimeInterval(snooze) < expiresAt ? {
            close()
            DispatchQueue.main.asyncAfter(deadline: .now() + snooze) {
                showAlert(title: title, start: start, join: join, docs: docs)
            }
        } : nil,
        join: join.isEmpty ? nil : {
            if let url = URL(string: join) { NSWorkspace.shared.open(url) }
            close()
            exit(0)
        })

    var subtitles: [NSTextField] = []
    var joinButtons: [PillButton] = []
    for screen in NSScreen.screens {
        let subtitle = NSTextField(labelWithString: subtitleText())
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitles.append(subtitle)
        let (panel, joinButton) = makePanel(on: screen, title: title, subtitle: subtitle,
                                            docs: docs, actions: actions)
        openPanels.append(panel)
        joinButton.map { joinButtons.append($0) }
    }

    timers.append(Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
        subtitles.forEach { $0.stringValue = subtitleText() }
    })
    timers.append(Timer.scheduledTimer(withTimeInterval: max(startDate.timeIntervalSinceNow, 0),
                                       repeats: false) { _ in
        subtitles.forEach { $0.stringValue = subtitleText() }
        joinButtons.forEach { $0.pulse() }
    })
    // Close on its own once the meeting is well underway.
    timers.append(Timer.scheduledTimer(withTimeInterval: max(expiresAt.timeIntervalSinceNow, 60),
                                       repeats: false) { _ in close(); exit(0) })

    openPanels.forEach { $0.orderFrontRegardless() }
    openPanels.first?.makeKey()
    NSSound(named: "Glass")?.play()
}

// Menu bar title drawn as a colored pill. SwiftBar can color title text but
// not its background, so the plugin shows this as an image instead. Rendered
// at 2x with the point size recorded in the PNG so it stays sharp on Retina.
func pill(text: String, background: String, foreground: String) -> String {
    func color(_ hex: String) -> NSColor {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.menuBarFont(ofSize: 0),
        .foregroundColor: color(foreground),
    ]
    let label = NSAttributedString(string: text, attributes: attrs)
    let padding: CGFloat = 7
    let height: CGFloat = 18
    let size = NSSize(width: ceil(label.size().width) + padding * 2, height: height)

    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color(background).setFill()
    NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 5, yRadius: 5).fill()
    label.draw(at: NSPoint(x: padding, y: (height - label.size().height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!.base64EncodedString()
}

// Icon for a row under a meeting: a "└" connector, which also indents the row
// since menus pin icons to the left edge, then either a page in the style of
// Google's file icons or, for "join", a video symbol. The join icon is used as
// a template image so it follows the menu's text color.
let indent: CGFloat = 12

func iconRep(kind: String, connector: Bool) -> NSBitmapImageRep {
    func rgb(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    let fill = ["doc": rgb(0x4285f4), "sheet": rgb(0x0f9d58), "slides": rgb(0xf4b400)][kind] ?? rgb(0x8e8e93)
    let lead = connector ? indent : 0
    let size = NSSize(width: lead + 16, height: 16)
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    if connector {
        let elbow = NSBezierPath()
        elbow.move(to: NSPoint(x: 5, y: 16))
        elbow.line(to: NSPoint(x: 5, y: 8))
        elbow.line(to: NSPoint(x: indent, y: 8))
        elbow.lineWidth = 1.2
        elbow.lineJoinStyle = .round
        (kind == "join" ? NSColor.black.withAlphaComponent(0.5) : rgb(0x8e8e93)).setStroke()
        elbow.stroke()

        let shift = NSAffineTransform()
        shift.translateX(by: indent, yBy: 0)
        shift.concat()
    }

    if kind == "join" {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        if let symbol = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let fit = min(1, 15 / symbol.size.width, 15 / symbol.size.height)
            let w = symbol.size.width * fit, h = symbol.size.height * fit
            symbol.draw(in: NSRect(x: (16 - w) / 2, y: (16 - h) / 2, width: w, height: h))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    let page = NSRect(x: 2.5, y: 0.5, width: 11, height: 15)
    let fold: CGFloat = 3.5
    let body = NSBezierPath()
    body.move(to: NSPoint(x: page.minX, y: page.minY))
    body.line(to: NSPoint(x: page.maxX, y: page.minY))
    body.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    body.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    body.line(to: NSPoint(x: page.minX, y: page.maxY))
    body.close()
    fill.setFill()
    body.fill()

    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    corner.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold))
    corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    corner.close()
    (fill.blended(withFraction: 0.35, of: .black) ?? fill).setFill()
    corner.fill()

    NSColor.white.setFill()
    let left = page.minX + 2.5
    let width = page.width - 5
    switch kind {
    case "sheet":
        NSRect(x: left, y: 3.5, width: width, height: 6).fill()
        fill.setFill()
        NSRect(x: left + width / 2 - 0.4, y: 3.5, width: 0.8, height: 6).fill()
        NSRect(x: left, y: 6.1, width: width, height: 0.8).fill()
    case "slides":
        NSRect(x: left, y: 4, width: width, height: 5).fill()
        fill.setFill()
        NSRect(x: left + 1, y: 5, width: width - 2, height: 3).fill()
    default:
        for y: CGFloat in [3.5, 6, 8.5] {
            NSRect(x: left, y: y, width: width, height: 1.2).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func fileIcon(kind: String) -> String {
    iconRep(kind: kind, connector: true).representation(using: .png, properties: [:])!.base64EncodedString()
}

func fileIconImage(kind: String) -> NSImage {
    let rep = iconRep(kind: kind, connector: false)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

let args = CommandLine.arguments
if args.count == 3, args[1] == "icon" {
    print(fileIcon(kind: args[2]))
    exit(0)
}
if args.count == 5, args[1] == "pill" {
    print(pill(text: args[2], background: args[3], foreground: args[4]))
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

switch args.count > 1 ? args[1] : "" {
case "events" where args.count == 3:
    // The permission prompt can sit unanswered; SwiftBar is blocked on
    // `open -W` meanwhile, so give up rather than hang the plugin.
    DispatchQueue.main.asyncAfter(deadline: .now() + watchdog) { exit(1) }
    writeEvents(to: args[2])
case "alert" where args.count == 5 || args.count == 6:
    // Docs arrive as base64 JSON so titles survive the shell's tab splitting.
    let docs = args.count == 6
        ? Data(base64Encoded: args[5]).flatMap { try? JSONDecoder().decode([Doc].self, from: $0) } ?? []
        : []
    DispatchQueue.main.async {
        showAlert(title: args[2], start: Int(args[3]) ?? 0, join: args[4], docs: docs)
    }
default:
    FileHandle.standardError.write(
        "usage: MeetingBarHelper events <out.json> | alert <title> <start> <join-url> [docs] | pill <text> <bg> <fg> | icon <kind>\n"
            .data(using: .utf8)!)
    exit(64)
}

app.run()
