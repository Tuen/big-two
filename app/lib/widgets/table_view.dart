import "package:big_two/rules/cards.dart";
import "package:big_two/sound/table_sounds.dart";
import "package:big_two/theme.dart";
import "package:big_two/widgets/playing_card_view.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

class SeatSpot {
  final String name;
  final int cardsLeft;
  final int total;
  final bool turn;
  final bool connected;
  final bool passing;
  const SeatSpot({
    required this.name,
    required this.cardsLeft,
    required this.total,
    required this.turn,
    this.connected = true,
    this.passing = false,
  });
}

class TableView extends StatefulWidget {
  final SeatSpot bottom;
  final SeatSpot left;
  final SeatSpot top;
  final SeatSpot right;
  final List<PlayingCard> hand;
  final Set<String> selected;
  final List<PlayingCard> trick;
  final String? trickLabel;
  final String? trickPlayer;
  final List<PlayingCard> previousCards;
  final String? previousLabel;
  final String? previousPlayer;
  final bool previousIsLastTrick;
  final bool yourTurn;
  final int playToken;
  final String trickOrigin;
  final int dealToken;
  final bool soundOn;
  final VoidCallback? onToggleSound;
  final bool canPlay;
  final bool canPass;
  final bool canUndo;
  final String passLabel;
  final String? reason;
  final String banner;
  final VoidCallback onPlay;
  final VoidCallback onPass;
  final VoidCallback? onUndo;
  final VoidCallback onSortRank;
  final VoidCallback onSortSuit;
  final VoidCallback onScores;
  final int chatUnread;
  final VoidCallback? onChat;
  final ValueChanged<String> onToggle;
  final void Function(int from, int to) onReorder;

  const TableView({
    super.key,
    required this.bottom,
    required this.left,
    required this.top,
    required this.right,
    required this.hand,
    required this.selected,
    required this.trick,
    required this.trickLabel,
    required this.trickPlayer,
    this.previousCards = const [],
    this.previousLabel,
    this.previousPlayer,
    this.previousIsLastTrick = false,
    this.yourTurn = false,
    this.playToken = 0,
    this.trickOrigin = "",
    this.dealToken = 0,
    this.soundOn = true,
    this.onToggleSound,
    required this.canPlay,
    required this.canPass,
    this.canUndo = false,
    required this.passLabel,
    required this.reason,
    required this.banner,
    required this.onPlay,
    required this.onPass,
    this.onUndo,
    required this.onSortRank,
    required this.onSortSuit,
    required this.onScores,
    this.chatUnread = 0,
    this.onChat,
    required this.onToggle,
    required this.onReorder,
  });

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> with TickerProviderStateMixin {
  final _stackKey = GlobalKey();
  final _pileKey = GlobalKey();
  final _bottomKey = GlobalKey();
  final _leftKey = GlobalKey();
  final _topKey = GlobalKey();
  final _rightKey = GlobalKey();
  late final AnimationController _flight;
  late final AnimationController _deal;
  late final AnimationController _pulse;
  int _seenPlay = 0;
  int _seenDeal = 0;
  List<PlayingCard> _flying = const [];
  double _flyWidth = 72;
  Offset? _flyFrom;
  Offset? _flyTo;

  @override
  void initState() {
    super.initState();
    _flight = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
    _deal = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..value = 1;
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _seenPlay = widget.playToken;
    _seenDeal = widget.dealToken;
    if (widget.dealToken > 0) {
      _deal.forward(from: 0);
    } else {
      _deal.value = 1;
    }
    if (widget.playToken > 0 && widget.trick.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startFlight());
    }
    if (widget.bottom.turn || widget.left.turn || widget.top.turn || widget.right.turn) {
      _pulse.forward();
    }
  }

  @override
  void didUpdateWidget(TableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playToken != _seenPlay) {
      _seenPlay = widget.playToken;
      _startFlight();
    }
    if (widget.dealToken != _seenDeal) {
      _seenDeal = widget.dealToken;
      _deal.forward(from: 0);
    }
    final nowSeat = _active(widget);
    final previousSeat = _active(oldWidget);
    if (nowSeat.isNotEmpty && nowSeat != previousSeat) _pulse.forward(from: 0);
  }

  String _active(TableView view) {
    if (view.bottom.turn) return "bottom";
    if (view.left.turn) return "left";
    if (view.top.turn) return "top";
    if (view.right.turn) return "right";
    return "";
  }

  @override
  void dispose() {
    _flight.dispose();
    _deal.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _startFlight() {
    if (widget.trick.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final from = _center(_originKey(widget.trickOrigin));
      final to = _center(_pileKey);
      if (from == null || to == null) return;
      setState(() {
        _flying = [...widget.trick];
        _flyWidth = 64;
        _flyFrom = from;
        _flyTo = to;
      });
      _flight.forward(from: 0);
    });
  }

  GlobalKey _originKey(String origin) {
    switch (origin) {
      case "left":
        return _leftKey;
      case "top":
        return _topKey;
      case "right":
        return _rightKey;
      default:
        return _bottomKey;
    }
  }

  Offset? _center(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final root = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || root == null || !box.hasSize || !root.hasSize) return null;
    return root.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): widget.canPlay ? widget.onPlay : () {},
        const SingleActivator(LogicalKeyboardKey.numpadEnter): widget.canPlay ? widget.onPlay : () {},
        const SingleActivator(LogicalKeyboardKey.keyP): widget.canPass ? widget.onPass : () {},
      },
      child: Focus(
        autofocus: true,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => TableSounds.instance.unlock(),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(colors: [felt, feltDeep], radius: 1.1),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final landscapePhone = constraints.maxWidth > constraints.maxHeight && constraints.maxHeight < 500;
                  final wide = !landscapePhone && constraints.maxWidth >= 900;
                  return Stack(
                    key: _stackKey,
                    children: [
                      if (landscapePhone) _landscape(constraints) else _stacked(constraints, wide),
                      _flightOverlay(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stacked(BoxConstraints constraints, bool wide) {
    return Column(
      children: [
        _topBar(compact: false),
        Expanded(child: wide ? _wide() : _portrait()),
        if (widget.banner.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(widget.banner, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        if (widget.yourTurn) _yourTurn(),
        KeyedSubtree(key: _bottomKey, child: _hand(constraints.maxWidth, constraints.maxWidth >= 900 ? 96 : 74)),
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 2, 48, 0),
          child: _plaque(widget.bottom, anchor: null, mine: true),
        ),
        if (widget.reason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
            child: Text(widget.reason!, textAlign: TextAlign.center, style: const TextStyle(color: gold, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(child: _actionButton(widget.passLabel, filled: false, onPressed: widget.canPass ? widget.onPass : null, buttonKey: const Key("pass-button"))),
              const SizedBox(width: 8),
              Expanded(child: _actionButton("Undo", filled: false, onPressed: widget.canUndo ? widget.onUndo : null, buttonKey: const Key("undo-button"))),
              const SizedBox(width: 8),
              Expanded(child: _actionButton("Play", filled: true, onPressed: widget.canPlay ? widget.onPlay : null, buttonKey: const Key("play-button"))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _landscape(BoxConstraints constraints) {
    final height = constraints.maxHeight;
    final bannerH = widget.banner.isEmpty ? 0.0 : 18.0;
    final turnH = widget.yourTurn ? 18.0 : 0.0;
    final reasonH = widget.reason == null ? 0.0 : 18.0;
    const topH = 40.0;
    const chipH = 54.0;
    const actionH = 60.0;
    final chrome = topH + chipH + bannerH + turnH + reasonH + actionH;
    var pileH = (height - chrome - 78).clamp(90.0, height);
    var handH = height - chrome - pileH;
    if (handH < 72) {
      handH = 72;
      pileH = height - chrome - handH;
      if (pileH < 90) {
        pileH = 90;
        handH = (height - chrome - pileH).clamp(0.0, height);
      }
    }
    final cardW = ((handH - 8) / 1.42).clamp(40.0, 92.0);
    return Column(
      children: [
        SizedBox(height: topH, child: _topBar(compact: true)),
        SizedBox(
          height: chipH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(child: _plaque(widget.left, compact: true, anchor: _leftKey)),
                Expanded(child: _plaque(widget.top, compact: true, anchor: _topKey)),
                Expanded(child: _plaque(widget.right, compact: true, anchor: _rightKey)),
              ],
            ),
          ),
        ),
        SizedBox(height: pileH, child: _pileRow(maxCardWidth: 70)),
        if (widget.banner.isNotEmpty)
          SizedBox(
            height: bannerH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(widget.banner, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        if (widget.yourTurn) SizedBox(height: turnH, child: _yourTurn(compact: true)),
        if (widget.reason != null)
          SizedBox(
            height: reasonH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(widget.reason!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: gold, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        SizedBox(
          height: handH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: KeyedSubtree(key: _bottomKey, child: _hand(constraints.maxWidth - 88, cardW, lift: 8))),
              SizedBox(
                width: 84,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 2),
                  child: _myLine(),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: actionH,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(
              children: [
                Expanded(child: _actionButton(widget.passLabel, filled: false, onPressed: widget.canPass ? widget.onPass : null, buttonKey: const Key("pass-button"))),
                const SizedBox(width: 12),
                Expanded(child: _actionButton("Undo", filled: false, onPressed: widget.canUndo ? widget.onUndo : null, buttonKey: const Key("undo-button"))),
                const SizedBox(width: 12),
                Expanded(child: _actionButton("Play", filled: true, onPressed: widget.canPlay ? widget.onPlay : null, buttonKey: const Key("play-button"))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(String label, {required bool filled, required VoidCallback? onPressed, Key? buttonKey}) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
    );
    final child = FittedBox(fit: BoxFit.scaleDown, child: Text(label));
    if (filled) return FilledButton(key: buttonKey, style: style, onPressed: onPressed, child: child);
    return OutlinedButton(key: buttonKey, style: style, onPressed: onPressed, child: child);
  }

  Widget _myLine() {
    final seat = widget.bottom;
    return Container(
      key: const Key("my-score"),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: seat.turn ? gold : Colors.white24),
      ),
      child: Text(
        "${seat.cardsLeft} · ${seat.total} pts",
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _yourTurn({bool compact = false}) {
    return Text(
      "Your turn",
      key: const Key("your-turn"),
      textAlign: TextAlign.center,
      style: TextStyle(color: gold, fontSize: compact ? 14 : 16, fontWeight: FontWeight.w800),
    );
  }

  Widget _topBar({required bool compact}) {
    final size = compact ? 13.0 : 15.0;
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final iconStyle = IconButton.styleFrom(
      minimumSize: const Size(32, 32),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: "Back",
            style: iconStyle,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(style: buttonStyle, onPressed: widget.onSortRank, child: Text("Sort rank", style: TextStyle(color: Colors.white, fontSize: size))),
                  TextButton(style: buttonStyle, onPressed: widget.onSortSuit, child: Text("Sort suit", style: TextStyle(color: Colors.white, fontSize: size))),
                  TextButton(style: buttonStyle, onPressed: widget.onScores, child: Text("Scores", style: TextStyle(color: gold, fontSize: compact ? 14 : 17, fontWeight: FontWeight.w800))),
                  if (widget.onChat != null)
                    Badge(
                      isLabelVisible: widget.chatUnread > 0,
                      label: Text("${widget.chatUnread}"),
                      child: IconButton(
                        key: const Key("chat-button"),
                        tooltip: "Chat",
                        style: iconStyle,
                        onPressed: widget.onChat,
                        icon: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 22),
                      ),
                    ),
                  IconButton(
                    tooltip: widget.soundOn ? "Mute sounds" : "Turn sounds on",
                    style: iconStyle,
                    onPressed: widget.onToggleSound,
                    icon: Icon(widget.soundOn ? Icons.volume_up : Icons.volume_off, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _portrait() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(child: _plaque(widget.left, anchor: _leftKey)),
              Expanded(child: _plaque(widget.top, anchor: _topKey)),
              Expanded(child: _plaque(widget.right, anchor: _rightKey)),
            ],
          ),
        ),
        Expanded(child: _pileRow(maxCardWidth: 72)),
      ],
    );
  }

  Widget _wide() {
    return Row(
      children: [
        SizedBox(width: 220, child: _plaque(widget.left, anchor: _leftKey)),
        Expanded(
          child: Column(
            children: [
              _plaque(widget.top, anchor: _topKey),
              Expanded(child: _pileRow(maxCardWidth: 78)),
            ],
          ),
        ),
        SizedBox(width: 220, child: _plaque(widget.right, anchor: _rightKey)),
      ],
    );
  }

  Widget _plaque(SeatSpot seat, {bool compact = false, GlobalKey? anchor, bool mine = false}) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final alpha = seat.turn ? 0.35 + 0.45 * _pulse.value : 0.0;
        return Container(
          key: mine ? const Key("my-score") : anchor,
          margin: EdgeInsets.all(compact ? 2 : 6),
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 3 : 8),
          decoration: BoxDecoration(
            color: seat.turn ? const Color(0xFF145C34) : const Color(0x66000000),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: seat.turn ? gold : Colors.white24, width: seat.turn ? 3 : 1),
            boxShadow: seat.turn
                ? [BoxShadow(color: gold.withValues(alpha: alpha), blurRadius: 16, spreadRadius: 1)]
                : const [],
          ),
          child: child,
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                seat.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 13 : 18, fontWeight: FontWeight.w800),
              ),
              Text(
                compact ? "${seat.cardsLeft} · ${seat.total} pts" : "${seat.cardsLeft} cards",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 12 : 16),
              ),
              if (!compact) Text("${seat.total} pts", style: const TextStyle(color: Colors.white70)),
              if (seat.turn)
                Text("▶ Turn", style: TextStyle(color: gold, fontWeight: FontWeight.w800, fontSize: compact ? 12 : 14)),
              if (!seat.connected) const Text("Away", style: TextStyle(color: gold, fontWeight: FontWeight.w700)),
            ],
          ),
          if (seat.passing)
            Positioned(
              top: compact ? -6 : -10,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: const Text("Pass", style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pileRow({required double maxCardWidth}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : 220.0;
          final cardH = (maxH - 26).clamp(48.0, maxCardWidth * 1.42);
          final cardWidth = (cardH / 1.42).clamp(32.0, maxCardWidth);
          return Row(
            children: [
              Expanded(child: Center(child: _previousPile(cardWidth * 0.6))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: Center(child: _currentPile(cardWidth))),
            ],
          );
        },
      ),
    );
  }

  Widget _previousPile(double cardWidth) {
    final caption = widget.previousCards.isEmpty
        ? ""
        : widget.previousIsLastTrick
            ? "Last trick · ${widget.previousPlayer ?? ""}"
            : "${widget.previousPlayer ?? ""} · ${widget.previousLabel ?? ""}";
    return KeyedSubtree(
      key: const Key("previous-play"),
      child: Opacity(
        opacity: widget.previousCards.isEmpty ? 0.0 : 0.72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (caption.isNotEmpty)
              Text(caption, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.white70)),
            if (widget.previousCards.isNotEmpty) const SizedBox(height: 4),
            _cardRow(widget.previousCards, cardWidth),
          ],
        ),
      ),
    );
  }

  Widget _currentPile(double cardWidth) {
    final flying = _flight.isAnimating && _flying.isNotEmpty;
    return KeyedSubtree(
      key: const Key("pile"),
      child: Container(
        key: _pileKey,
        alignment: Alignment.center,
        child: widget.trick.isEmpty
            ? const Text("Lead any combination", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.white70))
            : Opacity(
                opacity: flying ? 0 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${widget.trickPlayer ?? ""}  ·  ${widget.trickLabel ?? ""}",
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    _cardRow(widget.trick, cardWidth),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _cardRow(List<PlayingCard> cards, double cardWidth) {
    if (cards.isEmpty) return const SizedBox(height: 4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : cardWidth * cards.length;
        final fit = cards.length <= 1 ? cardWidth : (width / cards.length).clamp(28.0, cardWidth);
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [for (final card in cards) PlayingCardView(card: card, width: fit)],
        );
      },
    );
  }

  Widget _hand(double width, double cardWidth, {double lift = 28}) {
    final count = widget.hand.length;
    final gap = count <= 1 ? cardWidth : ((width - 16 - cardWidth) / (count - 1)).clamp(12.0, cardWidth * 0.62);
    final height = cardWidth * 1.42 + lift;
    return AnimatedBuilder(
      animation: _deal,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_deal.value);
        return SizedBox(
          height: height,
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < count; index++)
                Positioned(
                  left: _fanLeft(width, cardWidth, gap, index, t),
                  bottom: (1 - t) * 12,
                  child: Opacity(
                    opacity: 0.25 + 0.75 * t,
                    child: _FanCard(
                      card: widget.hand[index],
                      selected: widget.selected.contains(widget.hand[index].id),
                      width: cardWidth,
                      onTap: () => widget.onToggle(widget.hand[index].id),
                      onMove: (delta) {
                        if (gap <= 0) return;
                        final target = (index + (delta / gap).round()).clamp(0, count - 1);
                        if (target != index) widget.onReorder(index, target);
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _fanLeft(double width, double cardWidth, double gap, int index, double t) {
    final end = 8 + gap * index;
    final start = (width - cardWidth) / 2;
    return start + (end - start) * t;
  }

  Widget _flightOverlay() {
    return AnimatedBuilder(
      animation: _flight,
      builder: (context, _) {
        if (_flyFrom == null || _flyTo == null || _flying.isEmpty || !_flight.isAnimating) {
          return const SizedBox.shrink();
        }
        final t = Curves.easeOutCubic.transform(_flight.value);
        final origin = Offset.lerp(_flyFrom, _flyTo, t)!;
        final width = _flyWidth;
        final total = _flying.length * (width * 0.55);
        return IgnorePointer(
          child: Stack(
            children: [
              for (var i = 0; i < _flying.length; i++)
                Positioned(
                  left: origin.dx - total / 2 + i * width * 0.55,
                  top: origin.dy - width * 0.71,
                  child: PlayingCardView(card: _flying[i], width: width),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FanCard extends StatefulWidget {
  final PlayingCard card;
  final bool selected;
  final double width;
  final VoidCallback onTap;
  final ValueChanged<double> onMove;
  const _FanCard({
    required this.card,
    required this.selected,
    required this.width,
    required this.onTap,
    required this.onMove,
  });

  @override
  State<_FanCard> createState() => _FanCardState();
}

class _FanCardState extends State<_FanCard> {
  double _moved = 0;

  @override
  Widget build(BuildContext context) {
    return PlayingCardView(
      card: widget.card,
      selected: widget.selected,
      width: widget.width,
      onTap: widget.onTap,
      onDragStart: (_) => _moved = 0,
      onDragUpdate: (details) => _moved += details.primaryDelta ?? 0,
      onDragEnd: (_) {
        widget.onMove(_moved);
        _moved = 0;
      },
    );
  }
}

class WinnerPulse extends StatefulWidget {
  final String text;
  const WinnerPulse({super.key, required this.text});

  @override
  State<WinnerPulse> createState() => _WinnerPulseState();
}

class _WinnerPulseState extends State<WinnerPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..repeat(reverse: true, count: 4);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Text(widget.text, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: gold)),
    );
  }
}
