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

Future<bool> confirmLeave(BuildContext context, {required bool host}) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(leaveTitle),
      content: Text(leaveMessage(host: host)),
      actions: [
        TextButton(
          key: const Key("leave-anyway"),
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Leave anyway"),
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
  final Widget child;
  const LeaveGate({super.key, required this.warn, required this.host, required this.child});

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
    final leave = await confirmLeave(context, host: widget.host);
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
