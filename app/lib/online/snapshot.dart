import "package:big_two/rules/game.dart";

class SeatInfo {
  final int seat;
  final String? name;
  final bool connected;
  final String? userId;
  final bool isBot;
  final String? difficulty;
  const SeatInfo({
    required this.seat,
    required this.name,
    required this.connected,
    required this.userId,
    this.isBot = false,
    this.difficulty,
  });
}

class TrickInfo {
  final int seat;
  final List<String> cards;
  final String label;
  const TrickInfo({required this.seat, required this.cards, required this.label});
}

class RecentAction {
  final int seq;
  final int seat;
  final String kind;
  final List<String> cards;
  final String label;
  const RecentAction({
    required this.seq,
    required this.seat,
    required this.kind,
    required this.cards,
    required this.label,
  });
}

class HandResultView {
  final List<int> cardsLeft;
  final List<int> handPoints;
  final List<int> runningTotals;
  final bool roundOver;
  final int? winner;
  final String? closedReason;
  final List<Map<String, dynamic>> bonuses;
  const HandResultView({
    required this.cardsLeft,
    required this.handPoints,
    required this.runningTotals,
    required this.roundOver,
    required this.winner,
    required this.closedReason,
    required this.bonuses,
  });
}

class HistoryHand {
  final int round;
  final int hand;
  final String date;
  final List<String> players;
  final List<int> cardsLeft;
  final List<int> handPoints;
  final List<int> totals;
  final List<Map<String, dynamic>> bonuses;
  final bool roundOver;
  final String? scoreStatus;
  final bool hasBots;
  final List<String> bots;
  final String commitment;
  final String deckReveal;
  const HistoryHand({
    required this.round,
    required this.hand,
    required this.date,
    required this.players,
    required this.cardsLeft,
    required this.handPoints,
    required this.totals,
    required this.bonuses,
    required this.roundOver,
    required this.scoreStatus,
    this.hasBots = false,
    this.bots = const [],
    required this.commitment,
    required this.deckReveal,
  });
}

class UndoPrompt {
  final int seat;
  final String name;
  final String openedAt;
  final bool youVoted;
  const UndoPrompt({
    required this.seat,
    required this.name,
    required this.openedAt,
    required this.youVoted,
  });
}

class TableSnapshot {
  final String tableId;
  final String code;
  final String status;
  final String hostId;
  final int you;
  final int season;
  final int round;
  final int hand;
  final Settings settings;
  final List<SeatInfo> seats;
  final List<String> yourCards;
  final List<int> counts;
  final int? turn;
  final bool firstLead;
  final TrickInfo? trick;
  final List<int> locked;
  final List<int> running;
  final String? commitment;
  final String? deckReveal;
  final String message;
  final HandResultView? result;
  final List<HistoryHand> history;
  final bool roundOver;
  final bool canDeal;
  final bool canNewRound;
  final bool canEditSettings;
  final String? turnStartedAt;
  final List<RecentAction> recent;
  final bool canUndo;
  final UndoPrompt? undo;
  final bool holding;

  const TableSnapshot({
    required this.tableId,
    required this.code,
    required this.status,
    required this.hostId,
    required this.you,
    required this.season,
    required this.round,
    required this.hand,
    required this.settings,
    required this.seats,
    required this.yourCards,
    required this.counts,
    required this.turn,
    required this.firstLead,
    required this.trick,
    required this.locked,
    required this.running,
    required this.commitment,
    required this.deckReveal,
    required this.message,
    required this.result,
    required this.history,
    required this.roundOver,
    required this.canDeal,
    required this.canNewRound,
    required this.canEditSettings,
    required this.turnStartedAt,
    this.recent = const [],
    this.canUndo = false,
    this.undo,
    this.holding = false,
  });

  factory TableSnapshot.fromJson(Map<String, dynamic> json) {
    final settingsJson = _map(json["settings"]);
    final trickJson = json["trick"];
    final resultJson = json["result"];
    return TableSnapshot(
      tableId: json["tableId"].toString(),
      code: json["code"].toString(),
      status: json["status"].toString(),
      hostId: json["hostId"].toString(),
      you: _int(json["you"]),
      season: _int(json["season"]),
      round: _int(json["round"]),
      hand: _int(json["hand"]),
      settings: Settings(
        passLocks: settingsJson["passLocks"] == true,
        straightsWrap: settingsJson["straightsWrap"] == true,
        turnTimerSeconds: _int(settingsJson["turnTimerSeconds"]),
        season: _int(settingsJson["season"]),
        timezone: settingsJson["timezone"]?.toString() ?? "Australia/Melbourne",
        firstRoundNumber: _int(settingsJson["firstRoundNumber"]),
      ),
      seats: [
        for (final seat in (json["seats"] as List))
          SeatInfo(
            seat: _int(_map(seat)["seat"]),
            name: _map(seat)["name"]?.toString(),
            connected: _map(seat)["connected"] == true,
            userId: _map(seat)["userId"]?.toString(),
            isBot: _map(seat)["isBot"] == true,
            difficulty: _map(seat)["difficulty"]?.toString(),
          ),
      ],
      yourCards: [for (final card in (json["yourCards"] as List? ?? const [])) card.toString()],
      counts: _ints(json["counts"]),
      turn: json["turn"] == null ? null : _int(json["turn"]),
      firstLead: json["firstLead"] == true,
      trick: trickJson == null
          ? null
          : TrickInfo(
              seat: _int(_map(trickJson)["seat"]),
              cards: [for (final card in (_map(trickJson)["cards"] as List)) card.toString()],
              label: _map(trickJson)["label"].toString(),
            ),
      locked: _ints(json["locked"]),
      running: _ints(json["running"]),
      commitment: json["commitment"]?.toString(),
      deckReveal: json["deckReveal"]?.toString(),
      message: json["message"]?.toString() ?? "",
      result: resultJson == null
          ? null
          : HandResultView(
              cardsLeft: _ints(_map(resultJson)["cardsLeft"]),
              handPoints: _ints(_map(resultJson)["handPoints"]),
              runningTotals: _ints(_map(resultJson)["runningTotals"]),
              roundOver: _map(resultJson)["roundOver"] == true,
              winner: _map(resultJson)["winner"] == null ? null : _int(_map(resultJson)["winner"]),
              closedReason: _map(resultJson)["closedReason"]?.toString(),
              bonuses: [for (final bonus in (_map(resultJson)["bonuses"] as List? ?? const [])) _map(bonus)],
            ),
      history: [
        for (final row in (json["history"] as List? ?? const []))
          HistoryHand(
            round: _int(_map(row)["round"]),
            hand: _int(_map(row)["hand"]),
            date: _map(row)["date"]?.toString() ?? "",
            players: [for (final name in (_map(row)["players"] as List)) name.toString()],
            cardsLeft: _ints(_map(row)["cardsLeft"]),
            handPoints: _ints(_map(row)["handPoints"]),
            totals: _ints(_map(row)["runningTotals"]),
            bonuses: [for (final bonus in (_map(row)["bonuses"] as List? ?? const [])) _map(bonus)],
            roundOver: _map(row)["roundOver"] == true,
            scoreStatus: _map(row)["scoreStatus"]?.toString(),
            hasBots: _map(row)["hasBots"] == true,
            bots: [for (final name in (_map(row)["bots"] as List? ?? const [])) name.toString()],
            commitment: _map(row)["commitment"]?.toString() ?? "",
            deckReveal: _map(row)["deckReveal"]?.toString() ?? "",
          ),
      ],
      roundOver: json["roundOver"] == true,
      canDeal: json["canDeal"] == true,
      canNewRound: json["canNewRound"] == true,
      canEditSettings: json["canEditSettings"] == true,
      turnStartedAt: json["turnStartedAt"]?.toString(),
      recent: [
        for (final row in (json["recent"] as List? ?? const []))
          RecentAction(
            seq: _int(_map(row)["seq"]),
            seat: _int(_map(row)["seat"]),
            kind: _map(row)["kind"]?.toString() == "play" ? "play" : "pass",
            cards: [for (final card in (_map(row)["cards"] as List? ?? const [])) card.toString()],
            label: _map(row)["label"]?.toString() ?? "",
          ),
      ],
      canUndo: json["canUndo"] == true,
      undo: _undoFrom(json["undo"]),
      holding: json["holding"] == true,
    );
  }
}

int _int(dynamic value) => value is int ? value : (value as num).toInt();

UndoPrompt? _undoFrom(Object? raw) {
  if (raw is! Map) return null;
  final map = _map(raw);
  return UndoPrompt(
    seat: _int(map["seat"]),
    name: map["name"]?.toString() ?? "A player",
    openedAt: map["openedAt"]?.toString() ?? "",
    youVoted: map["youVoted"] == true,
  );
}

List<int> _ints(dynamic value) => [for (final item in (value as List? ?? const [])) _int(item)];

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  return (value as Map).map((key, item) => MapEntry(key.toString(), item));
}
