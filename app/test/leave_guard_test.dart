import "package:big_two/widgets/leave_guard.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("a running hand warns the host and a guest, and a finished round does not", () {
    expect(
      shouldWarnBeforeLeaving(dealt: true, handInProgress: true, roundOver: false),
      isTrue,
    );
    expect(leaveMessage(host: true), leaveHostMessage);
    expect(leaveMessage(host: false), leaveGuestMessage);

    expect(
      shouldWarnBeforeLeaving(dealt: true, handInProgress: false, roundOver: false),
      isTrue,
    );
    expect(
      shouldWarnBeforeLeaving(dealt: true, handInProgress: false, roundOver: true),
      isFalse,
    );
    expect(
      shouldWarnBeforeLeaving(dealt: false, handInProgress: false, roundOver: false),
      isFalse,
    );
  });

  testWidgets("the host is warned mid-hand and Stay in game keeps the page", (tester) async {
    await _open(tester, warn: true, host: true);
    await _back(tester);
    expect(find.text(leaveTitle), findsOneWidget);
    expect(find.text(leaveHostMessage), findsOneWidget);
    expect(find.text(leaveGuestMessage), findsNothing);
    expect(find.widgetWithText(FilledButton, "Stay in game"), findsOneWidget);
    await tester.tap(find.text("Stay in game"));
    await tester.pumpAndSettle();
    expect(find.text(leaveTitle), findsNothing);
    expect(find.text("in game"), findsOneWidget);
  });

  testWidgets("another player gets the shorter warning mid-hand", (tester) async {
    await _open(tester, warn: true, host: false);
    await _back(tester);
    expect(find.text(leaveTitle), findsOneWidget);
    expect(find.text(leaveGuestMessage), findsOneWidget);
    expect(find.text(leaveHostMessage), findsNothing);
  });

  testWidgets("between hands, before anyone reaches 50, Leave anyway exits", (tester) async {
    await _open(tester, warn: true, host: false);
    await _back(tester);
    expect(find.text(leaveGuestMessage), findsOneWidget);
    await tester.tap(find.text("Leave anyway"));
    await tester.pumpAndSettle();
    expect(find.text("in game"), findsNothing);
    expect(find.text("open"), findsOneWidget);
  });

  testWidgets("once the round is over, back leaves with no warning", (tester) async {
    await _open(tester, warn: false, host: true);
    await _back(tester);
    expect(find.text(leaveTitle), findsNothing);
    expect(find.text("open"), findsOneWidget);
  });
}

Future<void> _open(WidgetTester tester, {required bool warn, required bool host}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LeaveGate(
              warn: warn,
              host: host,
              child: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      const Text("in game"),
                      IconButton(
                        tooltip: "Back",
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ));
        },
        child: const Text("open"),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
  expect(find.text("in game"), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip("Back"));
  await tester.pumpAndSettle();
}

