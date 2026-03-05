import threading
import objc
from datetime import datetime, timedelta
from EventKit import EKEventStore, EKEntityTypeEvent, EKAuthorizationStatusFullAccess
from Foundation import NSDate


class CalendarMonitor:
    """Polls macOS calendar for upcoming meetings with video call links."""

    POLL_INTERVAL = 60  # seconds
    LOOKAHEAD_MINUTES = 5

    def __init__(self, on_meeting_soon=None):
        self._store = EKEventStore.alloc().init()
        self._on_meeting_soon = on_meeting_soon
        self._timer: threading.Timer | None = None
        self._running = False
        self._notified_events: set[str] = set()  # event IDs we already notified about
        self._authorized = False

    def request_access(self) -> bool:
        """Request calendar access. Returns True if granted."""
        event = threading.Event()
        result = [False]

        def callback(granted, error):
            result[0] = granted
            if error:
                print(f"[calendar] Access error: {error}")
            event.set()

        self._store.requestFullAccessToEventsWithCompletion_(callback)
        event.wait(timeout=10)
        self._authorized = result[0]
        if self._authorized:
            print("[calendar] Calendar access granted")
        else:
            print("[calendar] Calendar access denied")
        return self._authorized

    def get_upcoming_events(self, minutes_ahead=None):
        """Get calendar events in the next N minutes."""
        if not self._authorized:
            return []
        if minutes_ahead is None:
            minutes_ahead = self.LOOKAHEAD_MINUTES

        now = NSDate.date()
        end = NSDate.dateWithTimeIntervalSinceNow_(minutes_ahead * 60)
        predicate = self._store.predicateForEventsWithStartDate_endDate_calendars_(now, end, None)
        events = self._store.eventsMatchingPredicate_(predicate)
        return events or []

    def _check_meetings(self):
        if not self._running:
            return
        try:
            events = self.get_upcoming_events()
            for event in events:
                event_id = event.eventIdentifier()
                if event_id in self._notified_events:
                    continue

                title = event.title() or "Untitled Meeting"
                location = event.location() or ""
                notes = event.notes() or ""
                url = event.URL()
                url_str = str(url) if url else ""

                # Check for video call links
                all_text = f"{location} {notes} {url_str}".lower()
                has_video_link = any(
                    kw in all_text
                    for kw in ["zoom.us", "meet.google", "teams.microsoft", "webex", "whereby"]
                )

                if has_video_link or True:  # notify for all meetings for now
                    self._notified_events.add(event_id)
                    start_time = event.startDate()
                    info = {
                        "id": event_id,
                        "title": title,
                        "start": start_time,
                        "location": location,
                        "has_video_link": has_video_link,
                    }
                    print(f"[calendar] Upcoming: {title} (video={has_video_link})")
                    if self._on_meeting_soon:
                        self._on_meeting_soon(info)
        except Exception as e:
            print(f"[calendar] Poll error: {e}")

        # Schedule next poll
        if self._running:
            self._timer = threading.Timer(self.POLL_INTERVAL, self._check_meetings)
            self._timer.daemon = True
            self._timer.start()

    def start(self):
        if not self._authorized:
            self.request_access()
        self._running = True
        self._check_meetings()
        print(f"[calendar] Monitoring started (polling every {self.POLL_INTERVAL}s)")

    def stop(self):
        self._running = False
        if self._timer:
            self._timer.cancel()
            self._timer = None
