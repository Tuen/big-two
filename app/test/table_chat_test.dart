import "package:big_two/online/snapshot.dart";
import "package:big_two/widgets/table_chat.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

List<ChatLine> _lines(int count) {
  return [
    for (var i = 1; i <= count; i++)
      ChatLine(
        id: i,
        name: "Ada",
        viewer: false,
        text: "message $i",
        notice: true,
      ),
  ];
}

Finder _line(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is! Text) return false;
    if (widget.data == text) return true;
    final plain = widget.textSpan?.toPlainText();
    return plain == text || plain?.endsWith("  $text") == true;
  }, description: "chat line $text");
}

ScrollPosition _position(WidgetTester tester) {
  final list = find.descendant(
    of: find.byType(TableChatSheet),
    matching: find.byType(ListView),
  );
  return tester.widget<ListView>(list).controller!.position;
}

Rect _listRect(WidgetTester tester) {
  final list = find.descendant(
    of: find.byType(TableChatSheet),
    matching: find.byType(ListView),
  );
  return tester.getRect(list);
}

bool _inView(WidgetTester tester, String text) {
  final finder = _line(text);
  if (finder.evaluate().isEmpty) return false;
  final list = _listRect(tester);
  final rect = tester.getRect(finder);
  return rect.bottom > list.top + 1 && rect.top < list.bottom - 1;
}

void _expectAtEnd(WidgetTester tester) {
  final position = _position(tester);
  expect(position.maxScrollExtent, greaterThan(400));
  expect(
    position.pixels,
    moreOrLessEquals(position.maxScrollExtent, epsilon: 1),
  );
}

void main() {
  testWidgets("opening or reopening the chat shows the latest message", (
    tester,
  ) async {
    final messages = _lines(40);
    await tester.pumpWidget(_Opener(messages: messages));

    await tester.tap(find.text("Open chat"));
    await tester.pumpAndSettle();
    _expectAtEnd(tester);
    expect(_inView(tester, "message 40"), isTrue);
    expect(_inView(tester, "message 1"), isFalse);

    _position(tester).jumpTo(0);
    await tester.pump();
    expect(_position(tester).pixels, 0);
    expect(_inView(tester, "message 1"), isTrue);

    await tester.tap(find.byKey(const Key("chat-hide")));
    await tester.pumpAndSettle();
    expect(find.text("Table chat"), findsNothing);

    await tester.tap(find.text("Open chat"));
    await tester.pumpAndSettle();
    _expectAtEnd(tester);
    expect(_inView(tester, "message 40"), isTrue);
    expect(_inView(tester, "message 1"), isFalse);
  });

  testWidgets(
    "new messages follow only when the reader is already near the bottom",
    (tester) async {
      final host = _ChatHost(messages: _lines(40));
      await tester.pumpWidget(host);
      await tester.pumpAndSettle();
      _expectAtEnd(tester);

      final state = tester.state<_ChatHostState>(find.byType(_ChatHost));
      state.receive("at-bottom");
      await tester.pumpAndSettle();
      _expectAtEnd(tester);
      expect(_inView(tester, "at-bottom"), isTrue);

      final away = _position(tester).maxScrollExtent - 200;
      _position(tester).jumpTo(away);
      await tester.pump();
      expect(_position(tester).pixels, moreOrLessEquals(away, epsilon: 1));

      state.replace([...state.messages]);
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, moreOrLessEquals(away, epsilon: 1));

      state.receive("while-reading");
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, moreOrLessEquals(away, epsilon: 1));
      expect(_inView(tester, "while-reading"), isFalse);

      final near = _position(tester).maxScrollExtent - 40;
      _position(tester).jumpTo(near);
      await tester.pump();
      state.receive("near-bottom");
      await tester.pumpAndSettle();
      _expectAtEnd(tester);
      expect(_inView(tester, "near-bottom"), isTrue);
    },
  );

  testWidgets("sending a message scrolls to the bottom", (tester) async {
    await tester.pumpWidget(_ChatHost(messages: _lines(40)));
    await tester.pumpAndSettle();
    _expectAtEnd(tester);

    _position(tester).jumpTo(0);
    await tester.pump();
    expect(_inView(tester, "message 1"), isTrue);

    await tester.tap(find.widgetWithText(FilledButton, "Send"));
    await tester.pump();
    expect(_position(tester).pixels, 0);

    await tester.enterText(find.byType(TextField), "hello table");
    await tester.tap(find.widgetWithText(FilledButton, "Send"));
    await tester.pumpAndSettle();
    _expectAtEnd(tester);
    expect(_inView(tester, "hello table"), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });
}

class _Opener extends StatelessWidget {
  final List<ChatLine> messages;
  const _Opener({required this.messages});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => TableChatSheet(
                  messages: messages,
                  closed: false,
                  onSend: (_) {},
                ),
              );
            },
            child: const Text("Open chat"),
          ),
        ),
      ),
    );
  }
}

class _ChatHost extends StatefulWidget {
  final List<ChatLine> messages;
  const _ChatHost({required this.messages});

  @override
  State<_ChatHost> createState() => _ChatHostState();
}

class _ChatHostState extends State<_ChatHost> {
  late List<ChatLine> messages = [...widget.messages];

  void replace(List<ChatLine> next) => setState(() => messages = next);

  void receive(String text) {
    setState(() {
      messages = [
        ...messages,
        ChatLine(
          id: (messages.isEmpty ? 0 : messages.last.id) + 1,
          name: "Bea",
          viewer: false,
          text: text,
        ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: TableChatSheet(
          messages: messages,
          closed: false,
          onSend: receive,
        ),
      ),
    );
  }
}
