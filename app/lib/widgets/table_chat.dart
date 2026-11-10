import "package:big_two/online/audience.dart";
import "package:big_two/online/snapshot.dart";
import "package:big_two/theme.dart";
import "package:flutter/material.dart";

class TableChatSheet extends StatefulWidget {
  final List<ChatLine> messages;
  final bool closed;
  final ValueChanged<String> onSend;
  const TableChatSheet({
    super.key,
    required this.messages,
    required this.closed,
    required this.onSend,
  });

  @override
  State<TableChatSheet> createState() => _TableChatSheetState();
}

class _TableChatSheetState extends State<TableChatSheet> {
  final _field = TextEditingController();
  final _scroll = ScrollController();

  /// Follow incoming lines when the reader is already this close to the latest one.
  static const _followDistance = 80.0;

  /// A long list only learns its real extent once the last line is built.
  static const _jumpPasses = 12;

  int _jumpGeneration = 0;
  bool _followOwnSend = false;

  @override
  void initState() {
    super.initState();
    if (widget.messages.isNotEmpty) _jumpToLatest();
  }

  @override
  void didUpdateWidget(TableChatSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameMessages(oldWidget.messages, widget.messages)) return;
    final follow = _followOwnSend || _nearBottom;
    _followOwnSend = false;
    if (follow) _jumpToLatest();
  }

  bool get _nearBottom {
    if (!_scroll.hasClients) return true;
    final position = _scroll.position;
    if (!position.hasPixels || !position.hasContentDimensions) return true;
    return position.maxScrollExtent - position.pixels <= _followDistance;
  }

  bool _sameMessages(List<ChatLine> previous, List<ChatLine> next) {
    if (identical(previous, next)) return true;
    if (previous.length != next.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (previous[i].id != next[i].id) return false;
    }
    return true;
  }

  void _jumpToLatest() {
    final generation = ++_jumpGeneration;
    _enqueueJump(generation, 0);
  }

  void _enqueueJump(int generation, int pass) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _jumpAfterLayout(generation, pass),
    );
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _jumpAfterLayout(int generation, int pass) {
    if (!mounted || generation != _jumpGeneration) return;
    if (!_scroll.hasClients) {
      if (pass + 1 < _jumpPasses) _enqueueJump(generation, pass + 1);
      return;
    }
    final position = _scroll.position;
    if (!position.hasPixels || !position.hasContentDimensions) {
      if (pass + 1 < _jumpPasses) _enqueueJump(generation, pass + 1);
      return;
    }
    final gap = position.maxScrollExtent - position.pixels;
    if (gap < 1) return;
    position.jumpTo(position.maxScrollExtent);
    if (pass + 1 < _jumpPasses) _enqueueJump(generation, pass + 1);
  }

  @override
  void dispose() {
    _jumpGeneration++;
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _field.text;
    if (rejectedChat(text) != null) return;
    _followOwnSend = true;
    widget.onSend(cleanedChat(text));
    _field.clear();
    _jumpToLatest();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    const Expanded(child: Text("Table chat", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                    TextButton(
                      key: const Key("chat-hide"),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Hide"),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text("No messages yet.", style: TextStyle(color: Colors.white70)))
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final line in messages)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: line.notice
                                  ? Text(line.text, style: const TextStyle(color: gold, fontWeight: FontWeight.w700))
                                  : Text.rich(TextSpan(children: [
                                      TextSpan(
                                        text: line.viewer ? "${line.name} (viewer)" : line.name,
                                        style: const TextStyle(fontWeight: FontWeight.w800, color: gold),
                                      ),
                                      TextSpan(text: "  ${line.text}"),
                                    ])),
                            ),
                        ],
                      ),
              ),
              if (widget.closed)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text("This game is over. The chat has been cleared."),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _field,
                          maxLength: chatLimit,
                          textInputAction: TextInputAction.send,
                          decoration: const InputDecoration(
                            hintText: "Message this table",
                            filled: true,
                            counterText: "",
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _send, child: const Text("Send")),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
