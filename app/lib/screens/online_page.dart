import "dart:async";

import "package:big_two/online/game_api.dart";
import "package:big_two/online/snapshot.dart";
import "package:big_two/rules/cards.dart";
import "package:big_two/rules/combo.dart";
import "package:big_two/rules/commit.dart";
import "package:big_two/rules/game.dart";
import "package:big_two/theme.dart";
import "package:big_two/widgets/score_sheet.dart";
import "package:big_two/widgets/table_view.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:supabase_flutter/supabase_flutter.dart";

const _timezones = [
  "Australia/Melbourne",
  "Australia/Sydney",
  "Australia/Brisbane",
  "Australia/Adelaide",
  "Australia/Perth",
  "Pacific/Auckland",
  "UTC",
];

class OnlinePage extends StatefulWidget {
  final GameApi api;
  final String name;
  final bool create;
  final String code;
  final bool sound;
  const OnlinePage({
    super.key,
    required this.api,
    required this.name,
    required this.create,
    required this.code,
    required this.sound,
  });

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  TableSnapshot? _view;
  String? _error;
  bool _busy = false;
  final Set<String> _selected = {};
  List<String> _order = [];
  Timer? _poll;
  Timer? _clock;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _view?.settings.turnTimerSeconds != 0) setState(() {});
    });
    _open();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await widget.api.ensureSession();
      final view = widget.create
          ? await widget.api.call("table", {"action": "create", "name": widget.name, "settings": _settingsJson(defaultSettings)})
          : await widget.api.call("table", {"action": "join", "name": widget.name, "code": widget.code});
      if (!mounted) return;
      setState(() => _accept(view));
      _listen(view.tableId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _listen(String tableId) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
    _channel = widget.api.client
        .channel("table-$tableId")
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: "public",
          table: "hands",
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "table_id", value: tableId),
          callback: (_) => _refresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: "public",
          table: "seats",
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "table_id", value: tableId),
          callback: (_) => _refresh(),
        )
        .subscribe();
  }

  Future<void> _refresh() async {
    final current = _view;
    if (current == null || _busy) return;
    _busy = true;
    try {
      final next = await widget.api.call("tick", {"tableId": current.tableId});
      if (mounted) setState(() => _accept(next));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _busy = false;
    }
  }

  Future<void> _send(String function, Map<String, dynamic> body) async {
    setState(() => _error = null);
    try {
      final next = await widget.api.call(function, body);
      if (widget.sound) {
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.mediumImpact();
      }
      if (mounted) setState(() => _accept(next));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _accept(TableSnapshot next) {
    final previous = _view;
    final changed = previous == null || previous.hand != next.hand || previous.yourCards.join(",") != next.yourCards.join(",");
    _view = next;
    _error = null;
    if (changed) {
      _selected.clear();
      _order = sortCards(parseCards(next.yourCards), "rank").map(formatCard).toList();
    } else {
      final ids = next.yourCards.toSet();
      _order = [..._order.where(ids.contains), ...next.yourCards.where((id) => !_order.contains(id))];
    }
  }

  Map<String, dynamic> _settingsJson(Settings settings) => {
        "passLocks": settings.passLocks,
        "straightsWrap": settings.straightsWrap,
        "turnTimerSeconds": settings.turnTimerSeconds,
        "season": settings.season,
        "timezone": settings.timezone,
        "firstRoundNumber": settings.firstRoundNumber,
      };

  HandState? _local(TableSnapshot view) {
    if (view.turn == null) return null;
    final trickCards = view.trick?.cards ?? const <String>[];
    return makeState(
      hands: [for (var seat = 0; seat < 4; seat++) seat == view.you ? parseCards(view.yourCards) : <PlayingCard>[]],
      turn: view.turn!,
      running: view.running,
      firstLead: view.firstLead,
      trick: trickCards.isEmpty ? null : identify(parseCards(trickCards), wrap: view.settings.straightsWrap),
      trickSeat: view.trick?.seat,
      trickCards: trickCards,
      locked: view.locked,
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (view == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Online table")),
        body: Center(child: _error == null ? const CircularProgressIndicator() : _errorBox()),
      );
    }
    if (view.status == "playing") return _table(view);
    if (view.status == "hand_end" || view.status == "round_end") return _summary(view);
    return _lobby(view);
  }

  Widget _errorBox() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? "", textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _open, child: const Text("Try again")),
        ],
      ),
    );
  }

  Widget _lobby(TableSnapshot view) {
    final host = view.seats[view.you].userId == view.hostId;
    final full = view.seats.every((seat) => seat.userId != null);
    return Scaffold(
      appBar: AppBar(title: Text(full ? "Set the seating" : "Waiting for four")),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(view.code, textAlign: TextAlign.center, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: 6)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _copy(view), child: const Text("Copy code")),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: gold))),
          const SizedBox(height: 16),
          Text(view.message, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          for (var index = 0; index < view.seats.length; index++) _seatRow(view, index, host),
          if (host) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: view.seats.where((seat) => seat.userId != null).length < 2
                  ? null
                  : () => _send("table", {"action": "shuffle", "tableId": view.tableId}),
              child: const Text("Shuffle seats"),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text("The host can shuffle or move players before the deal."),
            ),
          if (host && view.canEditSettings) ...[
            SwitchListTile(
              value: view.settings.passLocks,
              title: const Text("Passing locks you out for the rest of the trick"),
              onChanged: (value) => _saveSettings(view, view.settings.copyWith(passLocks: value)),
            ),
            SwitchListTile(
              value: view.settings.straightsWrap,
              title: const Text("Straights can wrap"),
              onChanged: (value) => _saveSettings(view, view.settings.copyWith(straightsWrap: value)),
            ),
            const Text("Turn timer", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 8,
              children: [
                for (final seconds in [0, 15, 30, 45, 60])
                  ChoiceChip(
                    label: Text(seconds == 0 ? "Off" : "${seconds}s"),
                    selected: view.settings.turnTimerSeconds == seconds,
                    onSelected: (_) => _saveSettings(view, view.settings.copyWith(turnTimerSeconds: seconds)),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("Season ${view.season}"),
              trailing: _stepper(
                onMinus: () => _saveSettings(view, view.settings.copyWith(season: view.season - 1)),
                onPlus: () => _saveSettings(view, view.settings.copyWith(season: view.season + 1)),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("This round is ${view.round}"),
              trailing: _stepper(
                onMinus: () => _saveSettings(view, view.settings.copyWith(firstRoundNumber: view.round - 1)),
                onPlus: () => _saveSettings(view, view.settings.copyWith(firstRoundNumber: view.round + 1)),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Score date timezone"),
              subtitle: Text(view.settings.timezone),
              trailing: DropdownButton<String>(
                value: view.settings.timezone,
                dropdownColor: feltDeep,
                items: [
                  for (final zone in _timezones)
                    DropdownMenuItem(value: zone, child: Text(zone.split("/").last)),
                ],
                onChanged: (zone) {
                  if (zone != null) _saveSettings(view, view.settings.copyWith(timezone: zone));
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: view.canDeal ? () => _send("deal", {"tableId": view.tableId}) : null,
            child: const Text("Deal"),
          ),
        ],
      ),
    );
  }

  Widget _seatRow(TableSnapshot view, int index, bool host) {
    final seat = view.seats[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text("${index + 1}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(seat.name ?? "Empty seat", style: const TextStyle(fontSize: 22)),
                if (index == 0) const Text("Leads the first hand", style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
          Icon(seat.connected ? Icons.circle : Icons.circle_outlined, color: seat.name == null ? Colors.white24 : gold, size: 16),
          if (host) ...[
            IconButton(
              tooltip: "Rename",
              onPressed: seat.userId == null ? null : () => _renameSeat(view, index),
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              tooltip: "Move up",
              onPressed: index == 0 ? null : () => _moveSeat(view, index, index - 1),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: "Move down",
              onPressed: index == 3 ? null : () => _moveSeat(view, index, index + 1),
              icon: const Icon(Icons.arrow_downward),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _renameSeat(TableSnapshot view, int index) async {
    final seat = view.seats[index];
    final controller = TextEditingController(text: seat.name ?? "");
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Seat ${index + 1}"),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: "Name"),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text("Save")),
        ],
      ),
    );
    final name = entered?.trim() ?? "";
    controller.dispose();
    if (!mounted || name.isEmpty || name == seat.name) return;
    await _send("table", {"action": "rename", "tableId": view.tableId, "seat": index, "name": name});
  }

  Future<void> _moveSeat(TableSnapshot view, int from, int to) {
    final order = [for (final seat in view.seats) seat.userId];
    final moving = order[from];
    order[from] = order[to];
    order[to] = moving;
    return _send("table", {"action": "order", "tableId": view.tableId, "order": order});
  }

  Widget _stepper({required VoidCallback onMinus, required VoidCallback onPlus}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(onPressed: onMinus, icon: const Icon(Icons.remove_circle_outline)),
        IconButton(onPressed: onPlus, icon: const Icon(Icons.add_circle_outline)),
      ],
    );
  }

  Future<void> _saveSettings(TableSnapshot view, Settings settings) {
    return _send("table", {"action": "settings", "tableId": view.tableId, "settings": _settingsJson(settings)});
  }

  Future<void> _copy(TableSnapshot view) async {
    final link = kIsWeb ? "\n${Uri.base.origin}${Uri.base.path}?code=${view.code}" : "";
    await Clipboard.setData(ClipboardData(text: "Big Two table ${view.code}$link"));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code copied.")));
    }
  }

  Widget _table(TableSnapshot view) {
    final local = _local(view);
    final mine = view.turn == view.you;
    final selected = _selected.toList();
    final issue = !mine || local == null
        ? null
        : (selected.isEmpty ? "Select cards to play" : playIssue(local, view.you, parseCards(selected), view.settings));
    final leading = view.trick == null;
    final stuck = mine && local != null && leading && legalSelections(local, view.you, view.settings).isEmpty;
    final waiting = mine ? view.message : "Waiting for ${view.seats[view.turn ?? view.you].name ?? "the next player"}";
    final left = _remaining(view);
    return Scaffold(
      body: TableView(
        bottom: _spot(view, view.you),
        left: _spot(view, (view.you + 1) % 4),
        top: _spot(view, (view.you + 2) % 4),
        right: _spot(view, (view.you + 3) % 4),
        hand: [for (final id in _order) parseCard(id)],
        selected: _selected,
        trick: (view.trick?.cards ?? const []).map(parseCard).toList(),
        trickLabel: view.trick?.label,
        trickPlayer: view.trick == null ? null : view.seats[view.trick!.seat].name,
        canPlay: mine && issue == null,
        canPass: mine && (!leading || stuck),
        passLabel: stuck ? "Pass lead" : "Pass",
        reason: _error ?? (issue == null || selected.isEmpty ? null : issue),
        banner: left == null ? waiting : "$waiting  ·  ${left}s",
        onPlay: () => _send("play", {"tableId": view.tableId, "cards": selected}),
        onPass: () => _send("pass", {"tableId": view.tableId}),
        onSortRank: () => setState(() => _order = sortCards(parseCards(view.yourCards), "rank").map(formatCard).toList()),
        onSortSuit: () => setState(() => _order = sortCards(parseCards(view.yourCards), "suit").map(formatCard).toList()),
        onScores: () => _scores(view),
        onToggle: mine
            ? (id) => setState(() {
                if (!_selected.add(id)) _selected.remove(id);
              })
            : (_) {},
        onReorder: (from, to) => setState(() {
          final card = _order.removeAt(from);
          _order.insert(to, card);
        }),
      ),
    );
  }

  int? _remaining(TableSnapshot view) {
    if (view.turn != view.you || view.settings.turnTimerSeconds == 0 || view.turnStartedAt == null) return null;
    final started = DateTime.tryParse(view.turnStartedAt!);
    if (started == null) return null;
    final left = view.settings.turnTimerSeconds - DateTime.now().difference(started.toLocal()).inSeconds;
    return left < 0 ? 0 : left;
  }

  SeatSpot _spot(TableSnapshot view, int seat) {
    return SeatSpot(
      name: view.seats[seat].name ?? "Empty",
      cardsLeft: view.counts[seat],
      total: view.running[seat],
      turn: view.turn == seat,
      connected: view.seats[seat].connected,
    );
  }

  Widget _summary(TableSnapshot view) {
    final result = view.result;
    final names = [for (final seat in view.seats) seat.name ?? "Empty"];
    final winner = result?.winner == null ? "Nobody went out" : "${names[result!.winner!]} wins the hand";
    final matches = view.deckReveal == null || view.commitment == null
        ? null
        : commitDeck(parseCards(view.deckReveal!.split(","))).commitment == view.commitment;
    return Scaffold(
      appBar: AppBar(title: Text(view.roundOver ? "Round over" : "Hand over"), actions: [
        TextButton(onPressed: () => _scores(view), child: const Text("Scores")),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(winner, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (result != null)
            for (var seat = 0; seat < 4; seat++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  "${names[seat]}: ${result.cardsLeft[seat]} cards, ${result.handPoints[seat]} this hand, total ${result.runningTotals[seat]}",
                  style: TextStyle(fontSize: 18, color: result.runningTotals[seat] >= 50 ? gold : Colors.white),
                ),
              ),
          if (matches != null)
            Text(matches ? "The revealed deal matches the commitment." : "The revealed deal does not match.", style: const TextStyle(fontSize: 16)),
          if (_scoreLine(view) != null) Text(_scoreLine(view)!, style: const TextStyle(fontSize: 18)),
          if (_error != null) Text(_error!, style: const TextStyle(color: gold)),
          const SizedBox(height: 16),
          if (view.canNewRound) ...[
            const Text("The next screen sets the seating. The host can shuffle or move players, then someone deals."),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => _send("table", {"action": "new_round", "tableId": view.tableId}), child: const Text("New round")),
          ] else if (view.canDeal)
            FilledButton(onPressed: () => _send("deal", {"tableId": view.tableId}), child: const Text("Deal next hand")),
        ],
      ),
    );
  }

  Future<void> _scores(TableSnapshot view) {
    final names = [for (final seat in view.seats) seat.name ?? "Empty"];
    final matches = view.deckReveal != null && view.commitment != null && commitDeck(parseCards(view.deckReveal!.split(","))).commitment == view.commitment;
    return showScoreSheet(
      context: context,
      season: view.season,
      round: view.round,
      names: names,
      totals: view.running,
      handStillGoing: view.status == "playing",
      commitment: view.commitment,
      deckReveal: view.deckReveal,
      commitmentMatches: view.deckReveal == null ? null : matches,
      hands: [
        for (final hand in view.history)
          ScoreHand(
            round: hand.round,
            hand: hand.hand,
            date: hand.date,
            players: hand.players,
            cardsLeft: hand.cardsLeft,
            handPoints: hand.handPoints,
            totals: hand.totals,
            bonuses: hand.bonuses.map((bonus) => "${bonus["player"]} ${bonus["combo"]} +${bonus["pointsEach"]}").join("; "),
            roundOver: hand.roundOver,
            scoreStatus: hand.scoreStatus,
          ),
      ],
    );
  }

  String? _scoreLine(TableSnapshot view) {
    for (final hand in view.history.reversed) {
      if (hand.hand == view.hand && hand.round == view.round) return scoreDeliveryLabel(hand.scoreStatus);
    }
    return null;
  }
}
