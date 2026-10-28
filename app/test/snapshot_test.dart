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
    expect(view.watchers, isEmpty);
    expect(view.seats.first.standIn, isNull);
  });

  test("watcher names, a stand-in, and a table notice are parsed", () {
    final raw = _view();
    raw["watchers"] = ["Ralph", "Ada"];
    raw["viewerCount"] = 2;
    (raw["seats"] as List)[1] = {
      "seat": 1,
      "name": "Mary",
      "connected": true,
      "userId": "ralph",
      "isBot": false,
      "standIn": "watcher",
      "standInName": "Ralph",
    };
    raw["chat"] = [
      {"id": 3, "name": "Table", "viewer": false, "text": "Mary left. Ralph took their seat.", "notice": true},
    ];
    raw["history"] = [
      {
        "round": 1,
        "hand": 1,
        "date": "2026-10-27",
        "players": ["Justin", "Mary", "Pauline", "Damien"],
        "cardsLeft": [0, 1, 2, 3],
        "handPoints": [0, 1, 2, 3],
        "runningTotals": [0, 1, 2, 3],
        "bonuses": [],
        "roundOver": false,
        "scoreStatus": "sent",
        "commitment": "abc",
        "deckReveal": "3D",
        "standIns": [
          {"played": false, "who": null},
          {"played": true, "who": "Ralph"},
          {"played": false, "who": null},
          {"played": false, "who": null},
        ],
      },
    ];
    final view = TableSnapshot.fromJson(raw);
    expect(view.watchers, ["Ralph", "Ada"]);
    expect(view.seats[1].name, "Mary");
    expect(view.seats[1].standIn, "watcher");
    expect(view.seats[1].standInName, "Ralph");
    expect(view.chat.single.notice, isTrue);
    expect(view.chat.single.text, "Mary left. Ralph took their seat.");
    expect(view.history.single.standIns[1]["who"], "Ralph");
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
