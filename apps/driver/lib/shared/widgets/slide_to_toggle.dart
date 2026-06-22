import 'package:flutter/material.dart';

class SlideToToggle extends StatefulWidget {
  const SlideToToggle({
    super.key,
    required this.onTriggered,
    required this.label,
    this.enabled = true,
  });

  final VoidCallback onTriggered;
  final String label;
  final bool enabled;

  @override
  State<SlideToToggle> createState() => _SlideToToggleState();
}

class _SlideToToggleState extends State<SlideToToggle> {
  double _dragPosition = 0;
  static const double _width = 280;
  static const double _buttonSize = 50;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onHorizontalDragUpdate: widget.enabled
            ? (details) {
                setState(() {
                  _dragPosition -= details.delta.dx;
                  if (_dragPosition < 0) _dragPosition = 0;
                  final maxDrag = _width - _buttonSize - 8;
                  if (_dragPosition > maxDrag) _dragPosition = maxDrag;
                });
              }
            : null,
        onHorizontalDragEnd: widget.enabled
            ? (details) {
                final maxDrag = _width - _buttonSize - 8;
                if (_dragPosition >= maxDrag * 0.8) {
                  widget.onTriggered();
                }
                setState(() {
                  _dragPosition = 0;
                });
              }
            : null,
        child: Container(
          width: _width,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              PositionedDirectional(
                start: _dragPosition + 4,
                top: 2,
                bottom: 2,
                child: Container(
                  width: _buttonSize,
                  height: _buttonSize,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
