import "package:big_two/theme.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

class ScoreHand {
  final int round;
  final int hand;
  final String date;
  final List<String> players;
  final List<int> cardsLeft;
  final List<int> handPoints;
  final List<int> totals;
  final String bonuses;
  final bool roundOver;
  final String? scoreStatus;
  final String standInNote;
  const ScoreHand({
    required this.round,
    required this.hand,
    required this.date,
    required this.players,
    required this.cardsLeft,
    required this.handPoints,
    required this.totals,
    required this.bonuses,
    required this.roundOver,
    this.scoreStatus,
    this.standInNote = "",
  });
}

String? scoreDeliveryLabel(String? status) {
  switch (status) {
    case "sent":
      return "Scores sent ✓";
    case "failed":
      return "Scores failed";
    case "skipped":
      return "Scores not sent";
    case "pending":
    case "sending":
      return "Sending scores";
    default:
      return null;
  }
}

class Standing {
  final int rank;
  final String name;
  final int total;
  final int behind;
  final bool reached;
  const Standing(this.rank, this.name, this.total, this.behind, this.reached);
}

List<Standing> standings(List<String> names, List<int> totals) {
  final order = List.generate(names.length, (index) => index)
    ..sort((a, b) {
      final diff = totals[a].compareTo(totals[b]);
      return diff != 0 ? diff : a.compareTo(b);
    });
  final rows = <Standing>[];
  for (var place = 0; place < order.length; place++) {
    final seat = order[place];
    final behind = place == 0 ? 0 : totals[seat] - totals[order[place - 1]];
    rows.add(Standing(place + 1, names[seat], totals[seat], behind, totals[seat] >= 50));
  }
  return rows;
}

String roundCsv({
  required int season,
  required List<ScoreHand> hands,
}) {
  final buffer = StringBuffer("season,round,hand,date,player,cards_left,hand_points,running_total,round_over,bonuses\n");
  for (final hand in hands) {
    for (var seat = 0; seat < hand.players.length; seat++) {
      final bonus = seat == 0 ? hand.bonuses.replaceAll(",", ";") : "";
      buffer.write(
        "$season,${hand.round},${hand.hand},${hand.date},${_csv(hand.players[seat])},${hand.cardsLeft[seat]},${hand.handPoints[seat]},${hand.totals[seat]},${hand.roundOver},$bonus\n",
      );
    }
  }
  return buffer.toString();
}

String _csv(String value) => value.contains(",") ? '"${value.replaceAll('"', '""')}"' : value;

Future<void> showScoreSheet({
  required BuildContext context,
  required int season,
  required int round,
  required List<String> names,
  required List<int> totals,
  required bool handStillGoing,
  required List<ScoreHand> hands,
  bool practiceWithComputers = false,
  String? commitment,
  String? deckReveal,
  bool? commitmentMatches,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF10243A),
    builder: (context) {
      final rows = standings(names, totals);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 12),
              Text("Round $round  ·  Season $season", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              if (practiceWithComputers) ...[
                const SizedBox(height: 6),
                const Text("Practice (computer players)", style: TextStyle(fontSize: 18, color: gold, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 6),
              Text(
                handStillGoing ? "Card points are added when the hand ends. A bonus is already in the total." : "Lower score wins.",
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              ...rows.map((row) => _standingTile(row)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  final csv = roundCsv(season: season, hands: hands);
                  await Clipboard.setData(ClipboardData(text: csv));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Round CSV copied. Paste it into Excel.")));
                  }
                },
                child: const Text("Export round as CSV"),
              ),
              if (commitment != null) ...[
                const SizedBox(height: 16),
                Text("Deal check", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text("Published at the deal: $commitment", style: const TextStyle(fontSize: 13, color: Colors.white70)),
                if (deckReveal != null) Text(commitmentMatches == true ? "Revealed deck matches that commitment." : "The revealed deck does not match.", style: TextStyle(fontSize: 16, color: commitmentMatches == true ? const Color(0xFF9BE7A8) : cardRed)),
              ],
              const SizedBox(height: 16),
              const Text("Hands", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              if (hands.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text("No completed hands yet.")),
              ...hands.map(_handTile),
            ],
          );
        },
      );
    },
  );
}

Widget _standingTile(Standing row) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: row.reached ? const Color(0xFF5A1020) : const Color(0xFF1B3A2A),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: row.reached ? gold : Colors.white24),
    ),
    child: Row(
      children: [
        Text("${row.rank}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(width: 12),
        Expanded(child: Text(row.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text("${row.total}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(row.behind == 0 ? "Leading" : "${row.behind} behind", style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ],
    ),
  );
}

Widget _handTile(ScoreHand hand) {
  final bits = <String>[];
  for (var i = 0; i < hand.players.length; i++) {
    bits.add("${hand.players[i]} ${hand.cardsLeft[i]} cards, ${hand.handPoints[i]} pts");
  }
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Hand ${hand.hand}${hand.roundOver ? "  ·  round over" : ""}", style: const TextStyle(fontWeight: FontWeight.w700)),
        if (scoreDeliveryLabel(hand.scoreStatus) != null)
          Text(
            scoreDeliveryLabel(hand.scoreStatus)!,
            style: TextStyle(color: hand.scoreStatus == "failed" ? cardRed : const Color(0xFF9BE7A8)),
          ),
        Text(bits.join("\n"), style: const TextStyle(height: 1.35)),
        if (hand.bonuses.isNotEmpty) Text(hand.bonuses, style: const TextStyle(color: gold)),
        if (hand.standInNote.isNotEmpty) Text(hand.standInNote, style: const TextStyle(color: gold)),
      ],
    ),
  );
}
