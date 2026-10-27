import "package:big_two/widgets/leave_prompt_web.dart"
    if (dart.library.io) "package:big_two/widgets/leave_prompt_stub.dart";
import "package:flutter/material.dart";

const leaveTitle = "Leave this game?";

const leaveHostMessage =
    "The game isn't finished yet. If you leave now, the game may end for everyone.";

const leaveGuestMessage = "The game isn't finished yet. Are you sure you want to leave?";

/// Ask before leaving once a hand has been dealt and the round is not over.
/// A hand still being played always asks, even if a running total is already 50.
/// Before the first deal, and after the round is over, leaving is immediate.
bool shouldWarnBeforeLeaving({
  required bool dealt,
  required bool handInProgress,
  required bool roundOver,
}) {
  if (!dealt) return false;
  if (handInProgress) return true;
  return !roundOver;
}

String leaveMessage({required bool host}) => host ? leaveHostMessage : leaveGuestMessage;

const exitTitle = "Exit this game?";

const exitMessage =
    "If someone is watching, the person who started watching first takes your seat, cards, and turn. If nobody is watching, a computer takes the seat. Your score stays under your name.";

const lobbyExitTitle = "Exit this table?";

const lobbyExitMessage = "This frees your seat so someone else can join. Going back keeps the seat.";

const watchExitTitle = "Stop watching?";

const watchExitMessage = "You leave the watching list. The players keep their seats.";

/// Shown when someone goes back or closes the app during a game. The seat stays.
const seatHeldTitle = "Go back?";

const seatHeldMessage =
    "Your seat stays held. Closing the app does the same. Press Exit to give the seat to a watcher, or to a computer if nobody is watching.";

Future<bool> confirmLeave(BuildContext context, {required bool host}) async {
  return _confirm(
    context,
    title: leaveTitle,
    message: leaveMessage(host: host),
    confirm: "Leave anyway",
    confirmKey: "leave-anyway",
  );
}

Future<bool> confirmExit(BuildContext context) {
  return _confirm(context, title: exitTitle, message: exitMessage, confirm: "Exit", confirmKey: "confirm-exit");
}

Future<bool> confirmLobbyExit(BuildContext context) {
  return _confirm(
    context,
    title: lobbyExitTitle,
    message: lobbyExitMessage,
    confirm: "Exit",
    confirmKey: "confirm-exit",
  );
}

Future<bool> confirmStopWatching(BuildContext context) {
  return _confirm(
    context,
    title: watchExitTitle,
    message: watchExitMessage,
    confirm: "Exit",
    confirmKey: "confirm-exit",
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  required String confirmKey,
}) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          key: Key(confirmKey),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
        FilledButton(
          key: const Key("stay-in-game"),
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Stay in game"),
        ),
      ],
    ),
  );
  return leave == true;
}

/// Blocks the route's back button and gesture, and arms the browser's own
/// "Leave site?" prompt, while [warn] is true.
class LeaveGate extends StatefulWidget {
  final bool warn;
  final bool host;
  final String? title;
  final String? message;
  final Widget child;
  const LeaveGate({
    super.key,
    required this.warn,
    required this.host,
    this.title,
    this.message,
    required this.child,
  });

  @override
  State<LeaveGate> createState() => _LeaveGateState();
}

class _LeaveGateState extends State<LeaveGate> {
  bool _confirmed = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    setPageLeavePrompt(widget.warn);
  }

  @override
  void didUpdateWidget(LeaveGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.warn != widget.warn || _confirmed) {
      setPageLeavePrompt(widget.warn && !_confirmed);
    }
  }

  @override
  void dispose() {
    setPageLeavePrompt(false);
    super.dispose();
  }

  Future<void> _ask() async {
    if (_asking || !mounted) return;
    _asking = true;
    final leave = await _confirm(
      context,
      title: widget.title ?? leaveTitle,
      message: widget.message ?? leaveMessage(host: widget.host),
      confirm: "Leave anyway",
      confirmKey: "leave-anyway",
    );
    _asking = false;
    if (!leave || !mounted) return;
    setState(() => _confirmed = true);
    setPageLeavePrompt(false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.warn && !_confirmed;
    return PopScope(
      canPop: !block,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !block) return;
        _ask();
      },
      child: widget.child,
    );
  }
}
