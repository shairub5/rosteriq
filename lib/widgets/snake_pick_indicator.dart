import 'package:flutter/material.dart';

import '../engine/snake_position.dart';

class SnakePickIndicator extends StatelessWidget {
  final SnakePickWindow window;

  const SnakePickIndicator({super.key, required this.window});

  @override
  Widget build(BuildContext context) {
    final onClock = window.isMyTurn;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: onClock ? Colors.green.shade700 : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        onClock
            ? "YOU'RE ON THE CLOCK — pick${window.myPicksThisTurn.length > 1 ? 's' : ''} "
                '${window.myPicksThisTurn.join(" & ")}'
            : '${window.picksUntilMyTurn} pick${window.picksUntilMyTurn == 1 ? '' : 's'} until your turn '
                '(pick ${window.myPicksThisTurn.first})',
        style: TextStyle(
          color: onClock ? Colors.white : null,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
