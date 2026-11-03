import "package:big_two/online/presence.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("the fallback poll sits between five and ten seconds", () {
    expect(fallbackPollSeconds, inInclusiveRange(5, 10));
  });

  test("a hidden or backgrounded app does not poll, and a focused one does", () {
    expect(appIsVisible(AppLifecycleState.resumed), isTrue);
    expect(appIsVisible(AppLifecycleState.inactive), isTrue);
    expect(appIsVisible(AppLifecycleState.hidden), isFalse);
    expect(appIsVisible(AppLifecycleState.paused), isFalse);
    expect(appIsVisible(AppLifecycleState.detached), isFalse);
  });

  test("a seat write that only refreshes last_seen is not a table change", () {
    final before = {"seat_index": 0, "display_name": "Justin", "last_seen": "2026-11-03T00:00:00Z"};
    final presence = {"seat_index": 0, "display_name": "Justin", "last_seen": "2026-11-03T00:00:08Z"};
    final renamed = {"seat_index": 0, "display_name": "Mary", "last_seen": "2026-11-03T00:00:08Z"};
    expect(recordsArePresenceOnly(before, presence), isTrue);
    expect(recordsArePresenceOnly(before, renamed), isFalse);
    expect(recordsArePresenceOnly({}, presence), isFalse);
  });

  test("the turn timer is checked when it runs out, not on the slow poll", () {
    final started = DateTime.parse("2026-11-03T00:00:00Z");
    final early = refreshWaitForTurnTimer(
      timerSeconds: 30,
      turnStartedAt: started.toIso8601String(),
      now: started.add(const Duration(seconds: 10)),
      playing: true,
      blocked: false,
    );
    expect(early?.expired, isFalse);
    expect(early?.wait, const Duration(seconds: 20, milliseconds: 250));

    final late = refreshWaitForTurnTimer(
      timerSeconds: 30,
      turnStartedAt: started.toIso8601String(),
      now: started.add(const Duration(seconds: 31)),
      playing: true,
      blocked: false,
    );
    expect(late?.expired, isTrue);
    expect(late?.wait, const Duration(seconds: 2));

    expect(
      refreshWaitForTurnTimer(
        timerSeconds: 0,
        turnStartedAt: started.toIso8601String(),
        now: started,
        playing: true,
        blocked: false,
      ),
      isNull,
    );
    expect(
      refreshWaitForTurnTimer(
        timerSeconds: 30,
        turnStartedAt: started.toIso8601String(),
        now: started,
        playing: true,
        blocked: true,
      ),
      isNull,
    );
  });
}
