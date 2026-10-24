import "package:big_two/online/snapshot.dart";
import "package:flutter_test/flutter_test.dart";

Map<String, dynamic> _view({Object? recent}) {
  return {
    "tableId": "t1",
    "code": "ABC123",
    "status": "playing",
    "hostId": "host",
    "you": 0,
    "season": 24,
    "round": 1,
    "hand": 2,
    "settings": {
      "passLocks": false,
      "straightsWrap": false,
      "turnTimerSeconds": 0,
      "season": 24,
      "timezone": "Australia/Melbourne",
      "firstRoundNumber": 1,
    },
    "seats": [
      for (var seat = 0; seat < 4; seat++)
        {"seat": seat, "name": "Seat $seat", "connected": true, "userId": "u$seat", "isBot": seat != 0},
    ],
    "yourCards": ["AS", "KH"],
    "counts": [2, 13, 13, 13],
    "turn": 1,
    "firstLead": false,
    "trick": {"seat": 0, "cards": ["3D"], "label": "3"},
    "locked": [],
    "running": [0, 0, 0, 0],
    "message": "3",
    "roundOver": false,
    "canDeal": false,
    "canNewRound": false,
    "canEditSettings": false,
    if (recent != null) "recent": recent,
  };
}

void main() {
  test("an older snapshot without recent still parses", () {
    final view = TableSnapshot.fromJson(_view());
    expect(view.recent, isEmpty);
    expect(view.trick?.cards, ["3D"]);
    expect(view.yourCards, ["AS", "KH"]);
  });

  test("recent plays and passes are optional and parsed", () {
    final view = TableSnapshot.fromJson(_view(recent: [
      {"seq": 4, "seat": 1, "kind": "pass", "cards": [], "label": "Pass"},
      {"seq": 5, "seat": 2, "kind": "play", "cards": ["7S", "7H"], "label": "Pair of 7s"},
    ]));
    expect(view.recent, hasLength(2));
    expect(view.recent.first.kind, "pass");
    expect(view.recent.first.cards, isEmpty);
    expect(view.recent.last.kind, "play");
    expect(view.recent.last.cards, ["7S", "7H"]);
    expect(view.recent.last.label, "Pair of 7s");
  });
}
