import 'package:flutter/material.dart';

class PulsatingButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String text;

  const PulsatingButton({
    super.key,
    required this.onPressed,
    required this.text,
  });

  @override
  State<PulsatingButton> createState() => _PulsatingButtonState();
}

class _PulsatingButtonState extends State<PulsatingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget pulse(double delay, bool isDark) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = (_controller.value + delay) % 1.0;

        return Opacity(
          opacity: (1 - value) * 0.08,
          child: Transform.scale(
            scaleX: 1.0 + (value * 0.2),
            scaleY: 1.0 + (value * 0.7),
            child: child,
          ),
        );
      },
      child: Container(
        height: 54,
        width: 420,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          border: Border.all(
            color: isDark ? Colors.white : const Color(0xFF34495E),
            width: 2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final buttonColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0x2234495E);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.35)
        : const Color(0x6634495E);

    final textColor = isDark ? Colors.white : const Color(0xFF263746);

    return SizedBox(
      height: 70,
      width: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          pulse(0.0, isDark),
          pulse(0.33, isDark),
          pulse(0.66, isDark),

          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(27),
              child: Container(
                height: 54,
                width: 420,
                decoration: BoxDecoration(
                  color: buttonColor,
                  borderRadius: BorderRadius.circular(27),
                  border: Border.all(color: borderColor, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.text,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
