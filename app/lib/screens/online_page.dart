import "dart:async";

import "package:big_two/online/action_reel.dart";
import "package:big_two/online/audience.dart";
import "package:big_two/online/game_api.dart";
import "package:big_two/online/selection.dart";
import "package:big_two/online/snapshot.dart";
import "package:big_two/rules/cards.dart";
import "package:big_two/rules/combo.dart";
import "package:big_two/rules/commit.dart";
import "package:big_two/rules/game.dart";
import "package:big_two/sound/table_sounds.dart";
import "package:big_two/theme.dart";
import "package:big_two/widgets/full_table_prompt.dart";
import "package:big_two/widgets/leave_guard.dart";
import "package:big_two/widgets/score_sheet.dart";
import "package:big_two/widgets/table_chat.dart";
import "package:big_two/widgets/table_view.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";
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
  Timer? _pace;
  Timer? _undoTimer;
  Timer? _sweepTimer;
  Timer? _botTimer;
  Timer? _noPlay;
  Timer? _chatPoll;
  Timer? _pauseTimer;
  String? _noPlayCue;
  int? _chatSeen;
  bool _chatOpen = false;
  final _chatTick = ValueNotifier<int>(0);
  bool _undoDialog = false;
  String? _undoShown;
  DialogRoute<bool>? _undoRoute;
  RealtimeChannel? _channel;
  final ActionReel _reel = ActionReel();
  final Map<int, DateTime> _passUntil = {};
  bool _dwelling = false;
  int? _actor;
  int _playToken = 0;
  int _dealToken = 0;
  String _trickOrigin = "";
  late bool _sound;
  bool _left = false;
  String? _dealCue;
  String? _turnCue;
  String? _endCue;

  @override
  void initState() {
    super.initState();
    _sound = widget.sound;
    TableSounds.instance.enabled = _sound;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _view?.settings.turnTimerSeconds != 0) setState(() {});
    });
    _open();
  }

  @override
  void dispose() {
    // Closing the page does not exit the seat. Only the Exit button does.
    _poll?.cancel();
    _clock?.cancel();
    _pace?.cancel();
    _undoTimer?.cancel();
    _sweepTimer?.cancel();
    _botTimer?.cancel();
    _noPlay?.cancel();
    _pauseTimer?.cancel();
    _chatPoll?.cancel();
    _chatTick.dispose();
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
    } on GameException catch (error) {
      if (!mounted) return;
      final offered = !widget.create &&
          (error.message == "That table is full" || error.message == "That table has already started");
      if (!offered) {
        setState(() => _error = error.message);
        return;
      }
      final watch = await showDialog<bool>(
        context: context,
        builder: (context) => FullTablePrompt(message: error.message),
      );
      if (!mounted) return;
      if (watch != true) {
        Navigator.of(context).pop();
        return;
      }
      try {
        final view = await widget.api.call("table", {"action": "watch", "name": widget.name, "code": widget.code});
        if (!mounted) return;
        setState(() => _accept(view));
        _listen(view.tableId);
      } catch (watchError) {
        if (mounted) setState(() => _error = watchError.toString());
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _listen(String tableId) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
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
    setState(() {
      _error = null;
      _flushQueue();
    });
    TableSounds.instance.unlock();
    try {
      final next = await widget.api.call(function, body);
      if (_sound) HapticFeedback.mediumImpact();
      if (mounted) setState(() => _accept(next));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _accept(TableSnapshot next) {
    final previous = _view;
    final newHand = previous == null || previous.round != next.round || previous.hand != next.hand;
    final cardsChanged = previous == null || previous.yourCards.join(",") != next.yourCards.join(",");
    final trickWon = previous != null && previous.trick != null && next.trick == null && !newHand;
    final handEnded = previous != null && previous.status == "playing" && next.status != "playing";
    _view = next;
    _error = null;
    if (newHand || cardsChanged) {
      _order = sortCards(parseCards(next.yourCards), "rank").map(formatCard).toList();
    } else {
      final ids = next.yourCards.toSet();
      _order = [..._order.where(ids.contains), ...next.yourCards.where((id) => !_order.contains(id))];
    }
    if (dropSelection(newHand: newHand, cardsChanged: cardsChanged, trickWon: trickWon, handEnded: handEnded)) {
      _selected.clear();
    }
    _noteChat(next);
    _chatTick.value++;
    _syncReel(previous, next);
    _followUp(next);
  }

  void _noteChat(TableSnapshot next) {
    if (next.chat.isEmpty) return;
    final latest = next.chat.last.id;
    if (_chatOpen || _chatSeen == null) _chatSeen = latest;
  }

  int _unread(TableSnapshot view) => unreadChat([for (final line in view.chat) line.id], _chatSeen);

  String? _audience(TableSnapshot view) {
    return audienceLabel(names: view.watchers, count: view.viewerCount);
  }

  Widget _chatAction(TableSnapshot view) {
    return Badge(
      isLabelVisible: _unread(view) > 0,
      label: Text("${_unread(view)}"),
      child: IconButton(
        tooltip: "Chat",
        onPressed: () => _openChat(view),
        icon: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }

  Future<void> _openChat(TableSnapshot view) async {
    if (view.chat.isNotEmpty) setState(() => _chatSeen = view.chat.last.id);
    setState(() => _chatOpen = true);
    _chatPoll?.cancel();
    _chatPoll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return ValueListenableBuilder<int>(
          valueListenable: _chatTick,
          builder: (context, value, child) {
            final current = _view ?? view;
            return TableChatSheet(
              messages: current.chat,
              closed: current.status == "round_end" || current.roundOver,
              onSend: (text) => _send("table", {"action": "chat", "tableId": current.tableId, "text": text}),
            );
          },
        );
      },
    );
    _chatPoll?.cancel();
    _chatPoll = null;
    if (mounted) {
      final current = _view;
      setState(() {
        _chatOpen = false;
        if (current != null && current.chat.isNotEmpty) _chatSeen = current.chat.last.id;
      });
    }
  }

  void _armPause(TableSnapshot next) {
    _pauseTimer?.cancel();
    if (!next.holding) return;
    _pauseTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) _refresh();
    });
  }

  void _followUp(TableSnapshot next) {
    _armPause(next);
    if (next.watching) {
      _armBots(next);
      _armTwoSpades(next);
      return;
    }
    _armUndoClock(next);
    _armTwoSpades(next);
    _armBots(next);
    _armNoPlay(next);
    final undo = next.undo;
    if (undo == null) {
      _undoShown = null;
      if (_undoDialog) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _closeUndoDialog());
      }
      return;
    }
    if (undo.seat == next.you || undo.youVoted || _undoDialog || _undoShown == undo.openedAt) return;
    _undoShown = undo.openedAt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _view?.undo;
      if (current == null || current.openedAt != undo.openedAt || current.youVoted || current.seat == _view!.you) return;
      _askUndo(current, next.tableId);
    });
  }

  void _armUndoClock(TableSnapshot next) {
    _undoTimer?.cancel();
    final undo = next.undo;
    if (undo == null) return;
    final opened = DateTime.tryParse(undo.openedAt);
    if (opened == null) return;
    final wait = opened.add(const Duration(seconds: 30, milliseconds: 600)).difference(DateTime.now());
    _undoTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (mounted) _refresh();
    });
  }

  void _armNoPlay(TableSnapshot next) {
    final token = "${next.round}:${next.hand}:${next.turnStartedAt}";
    if (next.undo != null || next.holding || next.status != "playing" || next.turn != next.you) {
      _noPlay?.cancel();
      return;
    }
    final local = _local(next);
    if (local == null || !shouldAutoPass(local, next.you, next.settings)) {
      _noPlay?.cancel();
      return;
    }
    if (_noPlayCue == token) return;
    _noPlayCue = token;
    _noPlay?.cancel();
    _noPlay = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _refresh();
    });
  }

  void _armBots(TableSnapshot next) {
    _botTimer?.cancel();
    if (next.undo != null || next.holding) return;
    if (next.message == "2♠ – everyone passes") return;
    final turn = next.turn;
    if (turn == null || turn == next.you || turn < 0 || turn >= next.seats.length) return;
    if (!next.seats[turn].isBot) return;
    _botTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && _view?.undo == null) _refresh();
    });
  }

  void _armTwoSpades(TableSnapshot next) {
    _sweepTimer?.cancel();
    if (next.message != "2♠ – everyone passes") return;
    final turn = next.turn;
    if (turn == null || turn == next.you || !next.seats[turn].isBot) return;
    _sweepTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) _refresh();
    });
  }

  void _closeUndoDialog() {
    final route = _undoRoute;
    if (route == null || !route.isActive || !mounted) return;
    Navigator.of(context).removeRoute(route);
  }

  Future<void> _askUndo(UndoPrompt undo, String tableId) async {
    if (_undoDialog || !mounted) return;
    final navigator = Navigator.of(context);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (context) => AlertDialog(
        content: Text("${undo.name} wants to undo their last move."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Don't approve")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Approve")),
        ],
      ),
    );
    _undoRoute = route;
    _undoDialog = true;
    final answer = await navigator.push(route);
    _undoDialog = false;
    if (_undoRoute == route) _undoRoute = null;
    if (!mounted || answer == null) return;
    if (_view?.undo?.openedAt != undo.openedAt) return;
    await _send("table", {"action": "undo_vote", "tableId": tableId, "approve": answer});
  }

  void _syncReel(TableSnapshot? previous, TableSnapshot next) {
    final live = next.status == "playing" || next.status == "hand_end" || next.status == "round_end";
    if (!live || next.hand == 0) {
      _pace?.cancel();
      _pace = null;
      _dwelling = false;
      _actor = null;
      _reel.reset();
      return;
    }
    final freshHand = _reel.handKey != "${next.tableId}:${next.round}:${next.hand}";
    _reel.ingest("${next.tableId}:${next.round}:${next.hand}", next.recent);
    if (freshHand) {
      _align(next);
      _dwelling = false;
      _actor = null;
      _pace?.cancel();
      _pace = null;
      _cueDeal(previous, next);
      _cueEnd(next);
      return;
    }
    if (_reel.queue.isNotEmpty && !_dwelling && _pace == null) {
      _present();
      return;
    }
    if (_reel.queue.isEmpty && !_dwelling) {
      _align(next);
      _cueTurn(next);
      _cueEnd(next);
    }
  }

  void _present() {
    final action = _reel.pop();
    final view = _view;
    if (action == null || view == null) {
      _settle();
      return;
    }
    _dwelling = true;
    _actor = action.seat;
    if (action.kind == "pass") {
      _passUntil[action.seat] = DateTime.now().add(const Duration(milliseconds: 1500));
      TableSounds.instance.pass();
      Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() {});
      });
    } else {
      _playToken += 1;
      _trickOrigin = seatOrigin(action.seat, view.you);
      TableSounds.instance.playCard();
    }
    _pace?.cancel();
    _pace = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _dwelling = false;
        _pace = null;
        if (_reel.queue.isEmpty) {
          _settle();
        } else {
          _present();
        }
      });
    });
  }

  void _settle() {
    _dwelling = false;
    _actor = null;
    _pace?.cancel();
    _pace = null;
    final view = _view;
    if (view == null) return;
    _align(view);
    _cueTurn(view);
    _cueEnd(view);
  }

  void _flushQueue() {
    _pace?.cancel();
    _pace = null;
    _reel.flush();
    _dwelling = false;
    _actor = null;
    final view = _view;
    if (view != null) _align(view);
  }

  void _align(TableSnapshot view) {
    final trick = view.trick;
    if (trick == null) {
      _reel.align();
    } else {
      _reel.align(seat: trick.seat, cards: trick.cards, label: trick.label);
    }
  }

  void _cueDeal(TableSnapshot? previous, TableSnapshot next) {
    if (next.status != "playing") return;
    final token = "${next.round}:${next.hand}";
    if (_dealCue == token) return;
    final started = previous != null && (previous.status != "playing" || previous.round != next.round || previous.hand != next.hand);
    if (!started) return;
    _dealCue = token;
    _dealToken += 1;
    TableSounds.instance.deal();
  }

  void _cueTurn(TableSnapshot next) {
    if (_dwelling || _reel.queue.isNotEmpty) return;
    if (next.status != "playing" || next.turn != next.you) return;
    final token = "${next.round}:${next.hand}:${next.turn}:${next.turnStartedAt}";
    if (_turnCue == token) return;
    _turnCue = token;
    TableSounds.instance.yourTurn();
  }

  void _cueEnd(TableSnapshot next) {
    if (_dwelling || _reel.queue.isNotEmpty) return;
    if (next.status != "hand_end" && next.status != "round_end") return;
    final token = "${next.round}:${next.hand}";
    if (_endCue == token) return;
    _endCue = token;
    TableSounds.instance.handOver(roundOver: next.roundOver || next.status == "round_end");
  }

  Future<void> _toggleSound() async {
    final next = !_sound;
    setState(() {
      _sound = next;
      TableSounds.instance.enabled = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("sound", next);
  }

  bool _passing(int seat) {
    final until = _passUntil[seat];
    return until != null && until.isAfter(DateTime.now());
  }

  Map<String, dynamic> _settingsJson(Settings settings) => {
        "passLocks": settings.passLocks,
        "straightsWrap": settings.straightsWrap,
        "turnTimerSeconds": settings.turnTimerSeconds,
        "season": settings.season,
        "timezone": settings.timezone,
        "firstRoundNumber": settings.firstRoundNumber,
        "v13": true,
        if (const bool.fromEnvironment("TEST_PREVIEW")) "v14": true,
      };

  HandState? _local(TableSnapshot view) {
    if (view.turn == null) return null;
    final trickCards = view.trick?.cards ?? const <String>[];
    return makeState(
      hands: [
        for (var seat = 0; seat < 4; seat++)
          if (seat == view.you)
            parseCards(view.yourCards)
          else
            [
              for (var index = 0; index < (seat < view.counts.length ? view.counts[seat] : 0); index++)
                const PlayingCard(3, Suit.diamonds),
            ],
      ],
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
    final Widget page;
    if (view == null) {
      page = Scaffold(
        appBar: AppBar(title: const Text("Online table")),
        body: Center(child: _error == null ? const CircularProgressIndicator() : _errorBox()),
      );
    } else if (view.status == "playing" || _catchingUp(view)) {
      page = _table(view);
    } else if (view.status == "hand_end" || view.status == "round_end") {
      page = _summary(view);
    } else {
      page = _lobby(view);
    }
    final host = view != null && !view.watching && view.seats[view.you].userId == view.hostId;
    final playing = view?.status == "playing";
    final dealt = playing == true || view?.status == "hand_end" || view?.status == "round_end";
    final roundOver = view?.roundOver == true || view?.status == "round_end";
    final inGame = view != null &&
        !view.watching &&
        shouldWarnBeforeLeaving(dealt: dealt, handInProgress: playing == true, roundOver: roundOver);
    return LeaveGate(
      warn: inGame && !_left,
      host: host,
      title: inGame ? seatHeldTitle : null,
      message: inGame ? seatHeldMessage : null,
      child: page,
    );
  }

  Future<void> _exitTable(TableSnapshot view) async {
    final playing = view.status == "playing";
    final dealt = playing || view.status == "hand_end" || view.status == "round_end";
    final roundOver = view.roundOver || view.status == "round_end";
    final inGame = !view.watching &&
        shouldWarnBeforeLeaving(dealt: dealt, handInProgress: playing, roundOver: roundOver);
    final leave = view.watching
        ? await confirmStopWatching(context)
        : inGame
            ? await confirmExit(context)
            : await confirmLobbyExit(context);
    if (!leave || !mounted) return;
    try {
      await widget.api.leave(view.tableId);
      if (!mounted) return;
      setState(() => _left = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
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
    final host = !view.watching && view.seats[view.you].userId == view.hostId;
    final full = view.seats.every((seat) => seat.userId != null);
    return Scaffold(
      appBar: AppBar(
        title: Text(view.watching ? "Watching" : (full ? "Set the seating" : "Waiting for four")),
        actions: [
          TextButton(key: const Key("exit-table"), onPressed: () => _exitTable(view), child: const Text("Exit")),
          _chatAction(view),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(view.code, textAlign: TextAlign.center, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: 6)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _copy(view), child: const Text("Copy code")),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: gold))),
          const SizedBox(height: 16),
          Text(view.message, style: const TextStyle(fontSize: 18)),
          if (_audience(view) != null) ...[
            const SizedBox(height: 8),
            Text(_audience(view)!, key: const Key("watching-list"), style: const TextStyle(fontSize: 16, color: gold, fontWeight: FontWeight.w700)),
          ],
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
              child: Text("The host can add a computer player, shuffle seats, or rename players before the deal."),
            ),
          if (host && view.canEditSettings) ...[
            SwitchListTile(
              value: view.settings.passLocks,
              title: const Text("Passing locks you out for the rest of the trick"),
              onChanged: (value) => _saveSettings(view, view.settings.copyWith(passLocks: value)),
            ),
            SwitchListTile(
              value: view.settings.straightsWrap,
              title: const Text("Straight wrap"),
              subtitle: const Text("Saved with the table. A straight still cannot pass the 2."),
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
                Text(seat.name == null ? "Empty seat" : _seatTitle(seat), style: const TextStyle(fontSize: 22)),
                if (_standInDetail(seat) != null)
                  Text(_standInDetail(seat)!, style: const TextStyle(fontSize: 14, color: gold)),
                if (seat.isBot && seat.standIn == null)
                  Text("Computer · ${_difficultyLabel(seat.difficulty)}", style: const TextStyle(fontSize: 14)),
                if (index == 0) const Text("Leads the first hand", style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
          Icon(seat.connected ? Icons.circle : Icons.circle_outlined, color: seat.name == null ? Colors.white24 : gold, size: 16),
          if (host && seat.userId == null)
            IconButton(
              tooltip: "Add computer player",
              onPressed: () => _addBot(view, index),
              icon: const Icon(Icons.smart_toy_outlined),
            ),
          if (host && seat.isBot)
            IconButton(
              tooltip: "Remove computer player",
              onPressed: () => _send("table", {"action": "remove_bot", "tableId": view.tableId, "seat": index}),
              icon: const Icon(Icons.person_remove),
            ),
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

  String _seatTitle(SeatInfo seat) {
    final name = seat.name ?? "Empty";
    if (seat.standIn != null) return name;
    return seat.isBot ? "$name 🤖" : name;
  }

  String? _standInDetail(SeatInfo seat) {
    if (seat.standIn == "computer") return "Computer";
    if (seat.standIn == "watcher" && seat.standInName != null && seat.standInName!.isNotEmpty) {
      return seat.standInName;
    }
    return null;
  }

  String _difficultyLabel(String? difficulty) {
    switch (difficulty) {
      case "easy":
        return "Easy";
      case "hard":
        return "Hard";
      default:
        return "Normal";
    }
  }

  Future<void> _addBot(TableSnapshot view, int index) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) {
        var difficulty = "normal";
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text("Seat ${index + 1}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Add computer player"),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [("easy", "Easy"), ("normal", "Normal"), ("hard", "Hard")])
                      ChoiceChip(
                        label: Text(item.$2),
                        selected: difficulty == item.$1,
                        onSelected: (_) => setLocal(() => difficulty = item.$1),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              FilledButton(
                onPressed: () => Navigator.pop(context, difficulty),
                child: const Text("Add computer player"),
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    await _send("table", {"action": "add_bot", "tableId": view.tableId, "seat": index, "difficulty": chosen});
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

  bool _catchingUp(TableSnapshot view) {
    if (view.status != "hand_end" && view.status != "round_end") return false;
    return _dwelling || _reel.queue.isNotEmpty;
  }

  Widget _table(TableSnapshot view) {
    final local = _local(view);
    final mine = watcherCanAct(watching: view.watching, yourTurn: view.turn == view.you, allowed: true);
    final selected = _selected.toList();
    final issue = !mine || local == null
        ? null
        : (selected.isEmpty ? "Select cards to play" : playIssue(local, view.you, parseCards(selected), view.settings));
    final stuck = mine && local != null && stuckOnTwos(local, view.you, view.settings);
    final oneCard = mine && local != null && nextPlayerHasOneCard(local, view.you);
    final note = stuck
        ? onlyTwosLeadNote
        : (oneCard ? oneCardNote(local, view.you, view.settings) : null);
    final mayPass = mine && local != null && passIssue(local, view.you, view.settings) == null;
    final voting = view.undo != null;
    final paused = voting || view.holding;
    final shared = _everyoneSees(view.message);
    final lastCardWait = paused && mine && !voting && view.yourCards.length == 1;
    final waiting = mine || shared
        ? view.message
        : "Waiting for ${view.seats[view.turn ?? view.you].name ?? "the next player"}";
    final voteNote = voting ? "Waiting for the undo vote" : (lastCardWait ? "Playing your last card…" : null);
    final left = _remaining(view);
    final shownTurn = _dwelling && _actor != null ? _actor : view.turn;
    final counts = countsHolding(view.counts, _reel.queue);
    final trick = _reel.trick;
    final previous = _reel.previous;
    final trickName = trick == null ? null : view.seats[trick.seat].name;
    final previousName = previous == null ? null : view.seats[previous.seat].name;
    final audience = _audience(view);
    final banner = [
      if (audience != null) audience,
      if (left == null) waiting else "$waiting  ·  ${left}s",
    ].join("  ·  ");
    return Scaffold(
      body: TableView(
        bottom: _spot(view, view.you, turn: shownTurn == view.you, cards: counts[view.you]),
        left: _spot(view, (view.you + 1) % 4, turn: shownTurn == (view.you + 1) % 4, cards: counts[(view.you + 1) % 4]),
        top: _spot(view, (view.you + 2) % 4, turn: shownTurn == (view.you + 2) % 4, cards: counts[(view.you + 2) % 4]),
        right: _spot(view, (view.you + 3) % 4, turn: shownTurn == (view.you + 3) % 4, cards: counts[(view.you + 3) % 4]),
        hand: [for (final id in _order) parseCard(id)],
        selected: _selected,
        trick: (trick?.cards ?? const []).map(parseCard).toList(),
        trickLabel: trick?.label,
        trickPlayer: trickName,
        previousCards: (previous?.cards ?? const []).map(parseCard).toList(),
        previousLabel: previous?.label,
        previousPlayer: previousName,
        previousIsLastTrick: previous?.lastTrick ?? false,
        yourTurn: view.status == "playing" && mine,
        playToken: _playToken,
        trickOrigin: _trickOrigin,
        dealToken: _dealToken,
        soundOn: _sound,
        onToggleSound: _toggleSound,
        canPlay: canPressPlay(yourTurn: mine, paused: paused, issue: issue),
        canPass: mayPass && !paused,
        canUndo: !view.watching && view.canUndo && !paused,
        passLabel: stuck ? "Pass lead" : "Pass",
        reason: _error ?? voteNote ?? (issue == null || selected.isEmpty ? note : issue),
        banner: banner,
        onPlay: () {
          setState(_flushQueue);
          _send("play", {"tableId": view.tableId, "cards": selected});
        },
        onPass: () {
          setState(_flushQueue);
          _send("pass", {"tableId": view.tableId});
        },
        onUndo: () {
          _botTimer?.cancel();
          _send("table", {"action": "undo", "tableId": view.tableId});
        },
        onSortRank: () => setState(() => _order = sortCards(parseCards(view.yourCards), "rank").map(formatCard).toList()),
        onSortSuit: () => setState(() => _order = sortCards(parseCards(view.yourCards), "suit").map(formatCard).toList()),
        onScores: () => _scores(view),
        onExit: () => _exitTable(view),
        chatUnread: _unread(view),
        onChat: () => _openChat(view),
        onToggle: !view.watching && view.status == "playing"
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

  bool _everyoneSees(String message) {
    return message == noPlayMessage ||
        message == "You can't go out if you only have 2s. The lead passes on." ||
        message == "Undo rejected" ||
        message == "Move undone" ||
        message == "2♠ – everyone passes" ||
        message.endsWith("wants to undo their last move") ||
        message.endsWith("plays their last card");
  }

  int? _remaining(TableSnapshot view) {
    if (view.turn != view.you || view.settings.turnTimerSeconds == 0 || view.turnStartedAt == null) return null;
    final started = DateTime.tryParse(view.turnStartedAt!);
    if (started == null) return null;
    final left = view.settings.turnTimerSeconds - DateTime.now().difference(started.toLocal()).inSeconds;
    return left < 0 ? 0 : left;
  }

  SeatSpot _spot(TableSnapshot view, int seat, {required bool turn, required int cards}) {
    return SeatSpot(
      name: view.seats[seat].name == null ? "Empty" : _seatTitle(view.seats[seat]),
      cardsLeft: cards,
      total: view.running[seat],
      turn: turn,
      connected: view.seats[seat].connected,
      passing: _passing(seat),
      detail: _standInDetail(view.seats[seat]),
    );
  }

  Widget _summary(TableSnapshot view) {
    final result = view.result;
    final names = [for (final seat in view.seats) seat.name == null ? "Empty" : _seatTitle(seat)];
    final winner = result?.winner == null ? "Nobody went out" : "${names[result!.winner!]} wins the hand";
    final matches = view.deckReveal == null || view.commitment == null
        ? null
        : commitDeck(parseCards(view.deckReveal!.split(","))).commitment == view.commitment;
    return Scaffold(
      appBar: AppBar(title: Text(view.roundOver ? "Round over" : "Hand over"), actions: [
        if (_audience(view) != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(_audience(view)!, key: const Key("watching-list"), style: const TextStyle(color: gold)),
            ),
          ),
        TextButton(key: const Key("exit-table"), onPressed: () => _exitTable(view), child: const Text("Exit")),
        _chatAction(view),
        TextButton(onPressed: () => _scores(view), child: const Text("Scores")),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          WinnerPulse(text: winner),
          if (view.message.endsWith("plays their last card")) ...[
            const SizedBox(height: 8),
            Text(view.message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ],
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
    final names = [for (final seat in view.seats) seat.name == null ? "Empty" : _seatTitle(seat)];
    final matches = view.deckReveal != null && view.commitment != null && commitDeck(parseCards(view.deckReveal!.split(","))).commitment == view.commitment;
    final practice = view.seats.any((seat) => seat.isBot && seat.standIn == null) || view.history.any((hand) => hand.hasBots);
    return showScoreSheet(
      context: context,
      season: view.season,
      round: view.round,
      names: names,
      totals: view.running,
      handStillGoing: view.status == "playing",
      practiceWithComputers: practice,
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
            standInNote: _standInNote(hand.players, hand.standIns),
          ),
      ],
    );
  }

  String _standInNote(List<String> players, List<Map<String, dynamic>> standIns) {
    final bits = <String>[];
    for (var seat = 0; seat < standIns.length && seat < players.length; seat++) {
      final played = standIns[seat]["played"] == true;
      final who = standIns[seat]["who"]?.toString();
      if (played && who != null && who.isNotEmpty) bits.add("${players[seat]}: $who");
    }
    if (bits.isEmpty) return "";
    return "Stand-in played: ${bits.join("; ")}";
  }

  String? _scoreLine(TableSnapshot view) {
    for (final hand in view.history.reversed) {
      if (hand.hand == view.hand && hand.round == view.round) return scoreDeliveryLabel(hand.scoreStatus);
    }
    return null;
  }
}
