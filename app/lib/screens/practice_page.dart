import "dart:async";
import "dart:math";

import "package:big_two/rules/cards.dart";
import "package:big_two/rules/commit.dart";
import "package:big_two/rules/game.dart";
import "package:big_two/theme.dart";
import "package:big_two/widgets/score_sheet.dart";
import "package:big_two/widgets/table_view.dart";
import "package:flutter/material.dart" hide Step;
import "package:flutter/services.dart";

class PracticePage extends StatefulWidget {
  final List<String> names;
  final Settings settings;
  final bool sound;
  const PracticePage({super.key, required this.names, required this.settings, required this.sound});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  late Settings _settings;
  late List<String> _names;
  HandState? _state;
  HandResult? _result;
  final List<ScoreHand> _hands = [];
  List<int> _totals = [0, 0, 0, 0];
  int _round = 1;
  bool _cover = false;
  bool _startingRound = false;
  final Set<String> _selected = {};
  List<String> _order = [];
  String _banner = "";
  String? _reason;
  String? _commitment;
  String? _deck;
  Timer? _ticker;
  int? _secondsLeft;
  late final List<TextEditingController> _nameControllers;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _names = [...widget.names];
    _round = _settings.firstRoundNumber;
    _nameControllers = [for (final name in _names) TextEditingController(text: name)];
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _deal() {
    if (_startingRound) {
      _totals = [0, 0, 0, 0];
      _round += 1;
      _hands.clear();
      _startingRound = false;
    }
    final deck = shuffleDeck();
    final committed = commitDeck(deck);
    final first = _hands.isEmpty;
    final previous = _result?.winner;
    final state = startHand(deck, [..._totals], first, previous);
    setState(() {
      _state = state;
      _result = null;
      _deck = committed.canonical;
      _commitment = committed.commitment;
      _selected.clear();
      _order = sortCards(state.hands[state.turn], "rank").map(formatCard).toList();
      _banner = "Hand started. The deal commitment is saved in Scores.";
      _reason = null;
      _cover = true;
      _secondsLeft = null;
    });
    _ticker?.cancel();
  }

  void _reveal() {
    _ticker?.cancel();
    final seconds = _settings.turnTimerSeconds;
    setState(() {
      _cover = false;
      _secondsLeft = seconds == 0 ? null : seconds;
    });
    if (seconds == 0 || _state == null) return;
    final started = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _state == null || _cover) return;
      final left = seconds - DateTime.now().difference(started).inSeconds;
      if (left <= 0) {
        _ticker?.cancel();
        _apply(applyTimeout(_state!, _settings));
      } else {
        setState(() => _secondsLeft = left);
      }
    });
  }

  void _apply(Step step) {
    if (step is StepBad) {
      setState(() => _reason = step.message);
      return;
    }
    final ok = step as StepOk;
    final before = _state?.bonuses.length ?? 0;
    var banner = ok.message;
    if (ok.state.bonuses.length > before) {
      final bonus = ok.state.bonuses.last;
      banner = "${_names[bonus.seat]} played a ${bonus.combo}. +${bonus.pointsEach} to everyone else.";
    }
    if (widget.sound) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();
    }
    _ticker?.cancel();
    if (ok.state.status == "complete" && ok.result != null) {
      final result = ok.result!;
      final date = _today();
      final bonuses = result.bonuses.map((bonus) => "${_names[bonus.seat]} ${bonus.combo} +${bonus.pointsEach}").join("; ");
      setState(() {
        _state = ok.state;
        _result = result;
        _totals = [...result.runningTotals];
        _banner = banner;
        _reason = null;
        _cover = false;
        _selected.clear();
        _secondsLeft = null;
        _hands.add(ScoreHand(
          round: _round,
          hand: _hands.length + 1,
          date: date,
          players: [..._names],
          cardsLeft: result.cardsLeft,
          handPoints: result.handPoints,
          totals: result.runningTotals,
          bonuses: bonuses,
          roundOver: result.roundOver,
        ));
      });
      return;
    }
    setState(() {
      _state = ok.state;
      _banner = banner;
      _reason = null;
      _selected.clear();
      _cover = true;
      _order = sortCards(ok.state.hands[ok.state.turn], "rank").map(formatCard).toList();
      _secondsLeft = null;
    });
  }

  String _today() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, "0");
    final day = now.day.toString().padLeft(2, "0");
    return "${now.year}-$month-$day";
  }

  void _sort(String mode) {
    final state = _state;
    if (state == null || state.status != "playing") return;
    setState(() {
      _order = sortCards(state.hands[state.turn], mode).map(formatCard).toList();
    });
  }

  void _reorder(int from, int to) {
    setState(() {
      final card = _order.removeAt(from);
      _order.insert(to, card);
    });
  }

  Future<void> _scores() async {
    final state = _state;
    await showScoreSheet(
      context: context,
      season: _settings.season,
      round: _round,
      names: _names,
      totals: state == null ? _totals : (state.status == "complete" ? _totals : state.running),
      handStillGoing: state?.status == "playing",
      hands: _hands,
      commitment: _commitment,
      deckReveal: state?.status == "complete" ? _deck : null,
      commitmentMatches: state?.status == "complete" ? commitDeck(parseCards(_deck!.split(","))).commitment == _commitment : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) return _setup();
    if (_cover && state.status == "playing") return _coverScreen(state);
    if (state.status == "complete") return _summary(state);
    return _table(state);
  }

  void _swapSeats(int from, int to) {
    setState(() {
      final moving = _nameControllers[from].text;
      _nameControllers[from].text = _nameControllers[to].text;
      _nameControllers[to].text = moving;
    });
  }

  void _shuffleSeats() {
    final random = Random.secure();
    setState(() {
      final names = [for (final controller in _nameControllers) controller.text];
      shuffleInPlace(names, () => random.nextInt(0x100000000));
      for (var seat = 0; seat < names.length; seat++) {
        _nameControllers[seat].text = names[seat];
      }
    });
  }

  Widget _setup() {
    return Scaffold(
      appBar: AppBar(title: Text(_startingRound ? "Next round" : "This device")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _startingRound
                ? "Round ${_round + 1}. Change the seating, then deal. Seat 1 leads."
                : "Four players pass this phone around. Cards stay hidden between turns. Seat 1 leads.",
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 16),
          for (var seat = 0; seat < 4; seat++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameControllers[seat],
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: seat == 0 ? "Seat 1, leads" : "Seat ${seat + 1}",
                        filled: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "Move up",
                    onPressed: seat == 0 ? null : () => _swapSeats(seat, seat - 1),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: "Move down",
                    onPressed: seat == 3 ? null : () => _swapSeats(seat, seat + 1),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: _shuffleSeats, child: const Text("Shuffle seats")),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _settings.passLocks,
            title: const Text("Passing locks you out for the rest of the trick"),
            onChanged: (value) => setState(() => _settings = _settings.copyWith(passLocks: value)),
          ),
          SwitchListTile(
            value: _settings.straightsWrap,
            title: const Text("Straights can wrap"),
            onChanged: (value) => setState(() => _settings = _settings.copyWith(straightsWrap: value)),
          ),
          const Text("Turn timer", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 8,
            children: [
              for (final seconds in [0, 15, 30, 45, 60])
                ChoiceChip(
                  label: Text(seconds == 0 ? "Off" : "${seconds}s"),
                  selected: _settings.turnTimerSeconds == seconds,
                  onSelected: (_) => setState(() => _settings = _settings.copyWith(turnTimerSeconds: seconds)),
                ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("Season ${_settings.season}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(onPressed: () => setState(() => _settings = _settings.copyWith(season: _settings.season - 1)), icon: const Icon(Icons.remove_circle_outline)),
                IconButton(onPressed: () => setState(() => _settings = _settings.copyWith(season: _settings.season + 1)), icon: const Icon(Icons.add_circle_outline)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              _names = [for (final controller in _nameControllers) controller.text.trim()];
              if (_names.any((name) => name.isEmpty)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter all four names.")));
                return;
              }
              _deal();
            },
            child: const Text("Deal"),
          ),
        ],
      ),
    );
  }

  Widget _coverScreen(HandState state) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Pass the phone to", style: TextStyle(fontSize: 24)),
                const SizedBox(height: 8),
                Text(_names[state.turn], textAlign: TextAlign.center, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),
                FilledButton(onPressed: _reveal, child: const Text("Show my cards")),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _table(HandState state) {
    final seat = state.turn;
    final issue = _selected.isEmpty ? "Select cards to play" : playIssue(state, seat, parseCards(_selected.toList()), _settings);
    final leading = state.trick == null;
    final stuck = leading && legalSelections(state, seat, _settings).isEmpty;
    final timer = _secondsLeft == null ? "" : "  ·  ${_secondsLeft}s";
    return Scaffold(
      body: TableView(
        bottom: _spot(seat, state),
        left: _spot((seat + 1) % 4, state),
        top: _spot((seat + 2) % 4, state),
        right: _spot((seat + 3) % 4, state),
        hand: [for (final id in _order) parseCard(id)],
        selected: _selected,
        trick: state.trickCards.map(parseCard).toList(),
        trickLabel: state.trick?.label,
        trickPlayer: state.trickSeat == null ? null : _names[state.trickSeat!],
        canPlay: issue == null,
        canPass: !leading || stuck,
        passLabel: stuck ? "Pass lead" : "Pass",
        reason: _reason ?? (issue == null || _selected.isEmpty ? null : issue),
        banner: "$_banner$timer",
        onPlay: () => _apply(applyPlay(state, seat, _selected.toList(), _settings)),
        onPass: () => _apply(applyPass(state, seat, _settings)),
        onSortRank: () => _sort("rank"),
        onSortSuit: () => _sort("suit"),
        onScores: _scores,
        onToggle: (id) => setState(() {
          if (!_selected.add(id)) _selected.remove(id);
          _reason = null;
        }),
        onReorder: _reorder,
      ),
    );
  }

  SeatSpot _spot(int seat, HandState state) {
    return SeatSpot(
      name: _names[seat],
      cardsLeft: state.hands[seat].length,
      total: state.running[seat],
      turn: state.turn == seat,
    );
  }

  Widget _summary(HandState state) {
    final result = _result!;
    final winner = result.winner == null ? "Nobody went out" : "${_names[result.winner!]} wins the hand";
    return Scaffold(
      appBar: AppBar(title: Text(result.roundOver ? "Round over" : "Hand over"), actions: [
        TextButton(onPressed: _scores, child: const Text("Scores")),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(winner, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_banner, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          for (var seat = 0; seat < 4; seat++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                "${_names[seat]}: ${result.cardsLeft[seat]} cards, ${result.handPoints[seat]} this hand, total ${result.runningTotals[seat]}",
                style: TextStyle(fontSize: 18, color: result.runningTotals[seat] >= 50 ? gold : Colors.white),
              ),
            ),
          if (_deck != null && _commitment != null) ...[
            const SizedBox(height: 8),
            Text(
              commitDeck(parseCards(_deck!.split(","))).commitment == _commitment
                  ? "The revealed deal matches the commitment made at the start."
                  : "The revealed deal does not match.",
              style: const TextStyle(fontSize: 16),
            ),
          ],
          const SizedBox(height: 20),
          if (result.roundOver) ...[
            const Text("You can change the player order before the next round is dealt."),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => setState(() {
                _state = null;
                _result = null;
                _startingRound = true;
                _cover = false;
                _selected.clear();
              }),
              child: const Text("New round"),
            ),
          ] else
            FilledButton(onPressed: _deal, child: const Text("Deal next hand")),
        ],
      ),
    );
  }
}
