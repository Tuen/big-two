import "package:big_two/online/action_reel.dart";
import "package:big_two/online/snapshot.dart";
import "package:flutter_test/flutter_test.dart";

RecentAction act(int seq, int seat, String kind, List<String> cards, String label) {
  return RecentAction(seq: seq, seat: seat, kind: kind, cards: cards, label: label);
}

void main() {
  test("missed bot plays and passes are shown in order", () {
    final reel = ActionReel();
    expect(reel.ingest("hand-1", [act(1, 0, "play", ["3D"], "3")]), isTrue);
    expect(reel.queue, isEmpty);
    expect(reel.trick?.cards, ["3D"]);

    reel.ingest("hand-1", [
      act(1, 0, "play", ["3D"], "3"),
      act(2, 1, "pass", const [], "Pass"),
      act(3, 2, "play", ["4S"], "4"),
      act(4, 3, "pass", const [], "Pass"),
    ]);
    expect(reel.queue.map((event) => event.seq), [2, 3, 4]);

    expect(reel.pop()?.kind, "pass");
    expect(reel.trick?.cards, ["3D"]);
    expect(reel.pop()?.cards, ["4S"]);
    expect(reel.previous?.cards, ["3D"]);
    expect(reel.previous?.label, "3");
    expect(reel.pop()?.kind, "pass");
    expect(reel.queue, isEmpty);

    reel.align();
    expect(reel.trick, isNull);
    expect(reel.previous?.lastTrick, isTrue);
    expect(reel.previous?.cards, ["4S"]);
    expect(reel.previous?.seat, 2);
  });

  test("a new hand snaps instead of replaying old events", () {
    final reel = ActionReel();
    reel.ingest("hand-1", [act(3, 0, "play", ["3D"], "3")]);
    reel.ingest("hand-2", [act(1, 1, "play", ["KH"], "K"), act(2, 2, "pass", const [], "Pass")]);
    expect(reel.queue, isEmpty);
    expect(reel.cursor, 2);
    expect(reel.trick?.cards, ["KH"]);
  });

  test("flush applies the rest and counts wait for queued plays", () {
    final reel = ActionReel();
    reel.ingest("hand-1", const []);
    reel.ingest("hand-1", [act(1, 0, "play", ["3D"], "3"), act(2, 1, "play", ["5D", "5C"], "Pair of 5s")]);
    expect(countsHolding([12, 11, 13, 13], reel.queue), [13, 13, 13, 13]);
    reel.flush();
    expect(reel.queue, isEmpty);
    expect(reel.trick?.cards, ["5D", "5C"]);
    expect(reel.previous?.cards, ["3D"]);
    expect(countsHolding([12, 11, 13, 13], reel.queue), [12, 11, 13, 13]);
  });

  test("seat origin walks clockwise from you", () {
    expect(seatOrigin(0, 0), "bottom");
    expect(seatOrigin(1, 0), "left");
    expect(seatOrigin(2, 0), "top");
    expect(seatOrigin(3, 0), "right");
    expect(seatOrigin(0, 3), "left");
  });
}
