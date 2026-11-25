import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Shows the first of [children] that fits the height it is given, each
/// measured at the height it would take with no limit; when none fits, the
/// last one, which then has to make do with that height (by scrolling, say).
///
/// For content with a roomy and a tight form of the same thing: the tight
/// one appears exactly when the roomy one would be cut off, decided in the
/// same layout, with no frame in between that shows a clipped form.
///
/// Only the form shown is painted, hit, read to a screen reader, reachable
/// by keyboard focus, and found by a test's finders. The others stay built.
class VeilFirstThatFits extends StatefulWidget {
  const VeilFirstThatFits({super.key, required this.children}) : assert(children.length > 0);

  final List<Widget> children;

  @override
  State<VeilFirstThatFits> createState() => _VeilFirstThatFitsState();
}

class _VeilFirstThatFitsState extends State<VeilFirstThatFits> {
  // Which form the last layout showed. Focus follows one frame behind
  // layout, since a layout cannot rebuild what it lays out.
  int _shown = 0;

  void _handleShown(int index) {
    if (index == _shown) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && index != _shown) setState(() => _shown = index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _FirstThatFits(
      onShown: _handleShown,
      children: [
        for (final (index, child) in widget.children.indexed) ExcludeFocus(excluding: index != _shown, child: child),
      ],
    );
  }
}

class _FirstThatFits extends MultiChildRenderObjectWidget {
  const _FirstThatFits({required this.onShown, required super.children});

  final ValueChanged<int> onShown;

  @override
  MultiChildRenderObjectElement createElement() => _FirstThatFitsElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFirstThatFits(onShown);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderFirstThatFits renderObject) {
    renderObject.onShown = onShown;
  }
}

class _FirstThatFitsElement extends MultiChildRenderObjectElement {
  _FirstThatFitsElement(_FirstThatFits super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final shown = (renderObject as _RenderFirstThatFits).shown;
    for (final child in children) {
      if (child.renderObject == shown) visitor(child);
    }
  }
}

class _FitParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFirstThatFits extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _FitParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _FitParentData> {
  _RenderFirstThatFits(this.onShown);

  ValueChanged<int> onShown;

  /// The child the last layout chose.
  RenderBox? shown;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FitParentData) child.parentData = _FitParentData();
  }

  // A child's height with no limit on it, and then whether that fits.
  BoxConstraints get _unlimited => constraints.copyWith(minHeight: 0, maxHeight: double.infinity);

  @override
  void performLayout() {
    RenderBox? chosen;
    var chosenIndex = 0;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child), index++) {
      final isLast = child == lastChild;
      if (chosen != null) {
        // Not shown; laid out all the same, so it is ready when it is.
        child.layout(isLast ? constraints.loosen() : _unlimited);
        continue;
      }
      if (isLast) {
        child.layout(constraints.loosen(), parentUsesSize: true);
        chosen = child;
        chosenIndex = index;
        continue;
      }
      child.layout(_unlimited, parentUsesSize: true);
      if (child.size.height <= constraints.maxHeight) {
        chosen = child;
        chosenIndex = index;
      }
    }
    shown = chosen;
    size = constraints.constrain(chosen?.size ?? Size.zero);
    onShown(chosenIndex);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final unlimited = constraints.copyWith(minHeight: 0, maxHeight: double.infinity);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child == lastChild) return constraints.constrain(child.getDryLayout(constraints.loosen()));
      final natural = child.getDryLayout(unlimited);
      if (natural.height <= constraints.maxHeight) return constraints.constrain(natural);
    }
    return constraints.smallest;
  }

  // Asked for with no height to compare against: the roomy form's.
  @override
  double computeMinIntrinsicWidth(double height) => firstChild?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) => firstChild?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) => firstChild?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) => firstChild?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (shown case final child?) context.paintChild(child, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      shown?.hitTest(result, position: position) ?? false;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (shown case final child?) visitor(child);
  }
}
