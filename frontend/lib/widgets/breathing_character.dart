import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

class BreathingCharacter extends StatefulWidget {
  final String imagePath;

  const BreathingCharacter({super.key, required this.imagePath});

  @override
  State<BreathingCharacter> createState() => _BreathingCharacterState();
}

class _BreathingCharacterState extends State<BreathingCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: Image.asset(widget.imagePath),
      builder: (context, child) {
        final scaleY = 1.0 + (_controller.value * 0.05);

        return Transform(
          alignment: const Alignment(0.0, 0.35),
          transform: Matrix4.identity()
            ..scaleByVector3(Vector3(1.0, scaleY, 1.0)),
          child: child,
        );
      },
    );
  }
}
