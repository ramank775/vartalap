import 'package:flutter/material.dart';

class BouncingDots extends StatefulWidget {
  final Color color;
  final double size;

  const BouncingDots({
    super.key,
    this.color = Colors.white,
    this.size = 4.0,
  });

  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final double offset = (index * 0.2);
            double value = (_controller.value - offset);
            if (value < 0) value += 1.0;
            value = value > 0.5 ? 1.0 - value : value;
            value = value * 2.0; // scale to 0.0 - 1.0

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              height: widget.size,
              width: widget.size,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.3 + (value * 0.7)),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}
