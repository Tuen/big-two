import "table_sounds_web.dart" if (dart.library.io) "table_sounds_stub.dart" as impl;

/// Deal, play, pass, your turn, and hand over. Silent until the first tap.
class TableSounds {
  static final TableSounds instance = TableSounds._();
  TableSounds._();

  bool enabled = true;
  bool _unlocked = false;

  void unlock() {
    _unlocked = true;
    try {
      impl.unlockAudio();
    } catch (_) {
      // Autoplay can be blocked. Later taps try again.
    }
  }

  void deal() => _play(impl.playDeal);
  void playCard() => _play(impl.playCard);
  void pass() => _play(impl.playPass);
  void yourTurn() => _play(impl.playYourTurn);
  void handOver({required bool roundOver}) => _play(() => impl.playHandOver(roundOver));

  void _play(void Function() fn) {
    if (!enabled || !_unlocked) return;
    try {
      fn();
    } catch (_) {
      // A blocked or missing audio device must not break the table.
    }
  }
}
