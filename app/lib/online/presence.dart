import "package:flutter/widgets.dart";

/// Fallback poll while realtime is connected. Inside the 5–10 second band.
const fallbackPollSeconds = 8;

/// Hidden or backgrounded. Losing focus (inactive) still counts as on screen.
bool appIsVisible(AppLifecycleState state) {
  switch (state) {
    case AppLifecycleState.hidden:
    case AppLifecycleState.paused:
    case AppLifecycleState.detached:
      return false;
    case AppLifecycleState.resumed:
    case AppLifecycleState.inactive:
      return true;
  }
}

bool _sameValue(Object? left, Object? right) {
  if (left == right) return true;
  return left?.toString() == right?.toString();
}

/// A seat update that only bumps last_seen. The table itself did not change.
bool recordsArePresenceOnly(Map<String, dynamic> before, Map<String, dynamic> after) {
  if (before.isEmpty || after.isEmpty) return false;
  final keys = <String>{...before.keys, ...after.keys};
  var sawPresence = false;
  for (final key in keys) {
    if (key == "last_seen") {
      sawPresence = true;
      continue;
    }
    if (!_sameValue(before[key], after[key])) return false;
  }
  return sawPresence;
}

class TurnRefresh {
  final Duration wait;
  final bool expired;
  const TurnRefresh({required this.wait, required this.expired});
}

/// When to ask the server to apply a turn timer. Null when the timer is off.
/// A clock that has already run out is checked again two seconds later,
/// so one early reply does not wait for the slow fallback poll.
TurnRefresh? refreshWaitForTurnTimer({
  required int timerSeconds,
  required String? turnStartedAt,
  required DateTime now,
  required bool playing,
  required bool blocked,
}) {
  if (!playing || blocked || timerSeconds <= 0 || turnStartedAt == null) return null;
  final started = DateTime.tryParse(turnStartedAt);
  if (started == null) return null;
  final due = started.toLocal().add(Duration(seconds: timerSeconds));
  final remaining = due.difference(now);
  if (remaining.isNegative) return const TurnRefresh(wait: Duration(seconds: 2), expired: true);
  return TurnRefresh(wait: remaining + const Duration(milliseconds: 250), expired: false);
}
