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

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _send() {
    final text = _field.text;
    if (rejectedChat(text) != null) return;
    widget.onSend(cleanedChat(text));
    _field.clear();
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
