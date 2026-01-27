import 'package:flutter/material.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';

class DeskconnLoader extends StatefulWidget {
  final String? message;

  const DeskconnLoader({super.key, this.message});

  @override
  State<DeskconnLoader> createState() => _DeskconnLoaderState();
}

class _DeskconnLoaderState extends State<DeskconnLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.orange.withValues(alpha: 0.2),
          child: Center(
            child: FadeTransition(
              opacity: Tween(begin: 0.4, end: 1.0).animate(_controller),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DeskconnLogo(size: 64),
                  if (widget.message != null) ...[
                    const SizedBox(height: 16),
                    Text(widget.message!, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
