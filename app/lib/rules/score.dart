class Bonus {
  final int seat;
  final String kind;
  final String combo;
  final int pointsEach;
  const Bonus({required this.seat, required this.kind, required this.combo, required this.pointsEach});
}

/// 9 stays 9. 10, 11 and 12 double. 13 cards left score 36.
int cardPoints(int cardsLeft) {
  if (cardsLeft <= 0) return 0;
  if (cardsLeft == 13) return 36;
  if (cardsLeft >= 10 && cardsLeft <= 12) return cardsLeft * 2;
  return cardsLeft;
}

class HandScore {
  final List<int> cardsLeft;
  final List<int> cardPointList;
  final List<int> bonusReceived;
  final List<int> handPoints;
  final List<int> runningTotals;
  final bool roundOver;
  const HandScore({
    required this.cardsLeft,
    required this.cardPointList,
    required this.bonusReceived,
    required this.handPoints,
    required this.runningTotals,
    required this.roundOver,
  });
}

HandScore scoreCounts(List<int> cardsLeft, List<int> running, List<Bonus> bonuses) {
  final points = cardsLeft.map(cardPoints).toList();
  final bonusReceived = [0, 0, 0, 0];
  for (final bonus in bonuses) {
    for (var seat = 0; seat < 4; seat++) {
      if (seat != bonus.seat) bonusReceived[seat] += bonus.pointsEach;
    }
  }
  final handPoints = [for (var seat = 0; seat < 4; seat++) points[seat] + bonusReceived[seat]];
  final runningTotals = [for (var seat = 0; seat < 4; seat++) running[seat] + points[seat]];
  return HandScore(
    cardsLeft: [...cardsLeft],
    cardPointList: points,
    bonusReceived: bonusReceived,
    handPoints: handPoints,
    runningTotals: runningTotals,
    roundOver: runningTotals.any((total) => total >= 50),
  );
}

class WebhookPayload {
  final String handId;
  final String tableCode;
  final int season;
  final int round;
  final int hand;
  final String date;
  final List<String> players;
  final List<int> cardsLeft;
  final List<int> handPoints;
  final List<Map<String, Object>> bonuses;
  final List<int> runningTotals;
  final bool roundOver;
  final String? roundWinner;
  final bool hasBots;
  final List<String> bots;
  final List<Map<String, Object?>> standIns;
  const WebhookPayload({
    required this.handId,
    required this.tableCode,
    required this.season,
    required this.round,
    required this.hand,
    required this.date,
    required this.players,
    required this.cardsLeft,
    required this.handPoints,
    required this.bonuses,
    required this.runningTotals,
    required this.roundOver,
    required this.roundWinner,
    this.hasBots = false,
    this.bots = const [],
    this.standIns = const [
      {"played": false, "who": null},
      {"played": false, "who": null},
      {"played": false, "who": null},
      {"played": false, "who": null},
    ],
  });

  Map<String, Object?> toJson() => {
        "handId": handId,
        "tableCode": tableCode,
        "season": season,
        "round": round,
        "hand": hand,
        "date": date,
        "players": players,
        "cardsLeft": cardsLeft,
        "handPoints": handPoints,
        "bonuses": bonuses,
        "runningTotals": runningTotals,
        "roundOver": roundOver,
        "roundWinner": roundWinner,
        "hasBots": hasBots,
        "bots": bots,
        "standIns": standIns,
      };
}

/// Lowest total, in seat order. A tie lists every name. Null until the round is over.
String? roundWinnerName(List<String> players, List<int> totals, bool roundOver) {
  if (!roundOver || totals.isEmpty) return null;
  final best = totals.reduce((a, b) => a < b ? a : b);
  return [
    for (var seat = 0; seat < totals.length; seat++)
      if (totals[seat] == best) players[seat],
  ].join(", ");
}

WebhookPayload webhookPayload({
  required String handId,
  required String tableCode,
  required int season,
  required int round,
  required int hand,
  required String date,
  required List<String> players,
  required List<int> cardsLeft,
  required List<int> handPoints,
  required List<int> runningTotals,
  required bool roundOver,
  required List<Bonus> bonuses,
  bool hasBots = false,
  List<String> bots = const [],
  List<Map<String, Object?>>? standIns,
}) {
  return WebhookPayload(
    handId: handId,
    tableCode: tableCode,
    season: season,
    round: round,
    hand: hand,
    date: date,
    players: [...players],
    cardsLeft: [...cardsLeft],
    handPoints: [...handPoints],
    bonuses: [
      for (final bonus in bonuses)
        {"player": players[bonus.seat], "combo": bonus.combo, "pointsEach": bonus.pointsEach},
    ],
    runningTotals: [...runningTotals],
    roundOver: roundOver,
    roundWinner: roundWinnerName(players, runningTotals, roundOver),
    hasBots: hasBots,
    bots: [...bots],
    standIns: [
      for (final item in standIns ?? const [
        {"played": false, "who": null},
        {"played": false, "who": null},
        {"played": false, "who": null},
        {"played": false, "who": null},
      ])
        {"played": item["played"] == true, "who": item["who"]},
    ],
  );
}

/// A game (one round) is posted only after some running total reaches 50.
bool shouldPostGameScores(bool roundOver) => roundOver;

/// Same table, season, and round always produce the same id, so a retry can be skipped.
String gameIdFor(String tableId, int season, int round) => "$tableId:$season:$round";

const gamePayloadVersion = 1;

class GameWebhookPayload {
  final String type;
  final int version;
  final String gameId;
  final String tableCode;
  final int season;
  final int round;
  final String date;
  final List<String> players;
  final List<int> finalTotals;
  final String? winner;
  final List<WebhookPayload> hands;
  const GameWebhookPayload({
    required this.type,
    required this.version,
    required this.gameId,
    required this.tableCode,
    required this.season,
    required this.round,
    required this.date,
    required this.players,
    required this.finalTotals,
    required this.winner,
    required this.hands,
  });

  Map<String, Object?> toJson() => {
        "type": type,
        "version": version,
        "gameId": gameId,
        "tableCode": tableCode,
        "season": season,
        "round": round,
        "date": date,
        "players": players,
        "finalTotals": finalTotals,
        "winner": winner,
        "hands": [for (final hand in hands) hand.toJson()],
      };
}

/// One POST for a finished game. Each hand keeps the old field names.
/// [winner] is the lowest final total.
GameWebhookPayload gameWebhookPayload({
  required String gameId,
  required String tableCode,
  required int season,
  required int round,
  required String date,
  required List<String> players,
  required List<int> finalTotals,
  required List<WebhookPayload> hands,
}) {
  final ordered = [...hands]..sort((a, b) {
      final byHand = a.hand.compareTo(b.hand);
      return byHand != 0 ? byHand : a.handId.compareTo(b.handId);
    });
  final last = ordered.isEmpty ? null : ordered.last;
  final names = last == null ? [...players] : [...last.players];
  final totals = last == null ? [...finalTotals] : [...last.runningTotals];
  final finished = ordered.any((hand) => hand.roundOver);
  return GameWebhookPayload(
    type: "game",
    version: gamePayloadVersion,
    gameId: gameId,
    tableCode: tableCode,
    season: season,
    round: round,
    date: last?.date ?? date,
    players: names,
    finalTotals: totals,
    winner: roundWinnerName(names, totals, finished),
    hands: ordered,
  );
}
