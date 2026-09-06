// Reproduction probe for the r3 paint observation: the staff-entry card's
// yellow Ink decoration paints on the ANCESTOR Scaffold Material, so the
// capture boundary wraps the ENTIRE MaterialApp (nothing of the original
// paint owner is excluded). Baseline alignment is asserted BEFORE the async
// reflow; only a post-reflow misalignment after that valid baseline would
// reproduce r3. Raster conversion runs in tester.runAsync with bounded waits.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/presentation/restaurant_communication_entry_card.dart';

class _HeightChanger extends StatefulWidget {
  const _HeightChanger({required this.height});
  final ValueNotifier<double> height;
  @override
  State<_HeightChanger> createState() => _HeightChangerState();
}

class _HeightChangerState extends State<_HeightChanger> {
  @override
  void initState() {
    super.initState();
    widget.height.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    widget.height.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height.value,
      child: const SizedBox.expand(),
    );
  }
}

/// Painted yellow bounds of the FULL screen, in global coordinates.
Future<Rect?> _paintedYellowBounds(WidgetTester tester, GlobalKey boundaryKey) {
  return tester.runAsync<Rect?>(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final data = byteData!.buffer.asUint8List();
    int? left, top, right, bottom;
    // Entry background 0xFFFFF7E8 = (255, 247, 232); tight tolerance excludes
    // the lighter icon chip (0xFFFFE9B8) and the white scaffold.
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        if ((data[i] - 255).abs() <= 4 &&
            (data[i + 1] - 247).abs() <= 4 &&
            (data[i + 2] - 232).abs() <= 4) {
          if (left == null || x < left) left = x;
          if (right == null || x > right) right = x;
          if (top == null || y < top) top = y;
          if (bottom == null || y > bottom) bottom = y;
        }
      }
    }
    image.dispose();
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    final origin = boundary.localToGlobal(Offset.zero);
    return Rect.fromLTRB(
      left.toDouble() + origin.dx,
      top.toDouble() + origin.dy,
      right.toDouble() + origin.dx,
      bottom.toDouble() + origin.dy,
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('painted yellow background follows the card after async reflow', (
    tester,
  ) async {
    tester.view.physicalSize = const ui.Size(402.0, 874.0);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = TravelPreferencesStore();
    await store.ensureLoaded();
    final height = ValueNotifier<double>(80.0);
    // Boundary OUTSIDE MaterialApp: the ancestor Scaffold Material that owns
    // the original Ink paint is fully included in the capture.
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                _HeightChanger(height: height),
                RestaurantCommunicationEntryCard(language: 'en', store: store),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Rect entryRect() {
      final entryBox = tester.renderObject<RenderBox>(
        find.byType(RestaurantCommunicationEntryCard),
      );
      return Rect.fromLTWH(
        entryBox.localToGlobal(Offset.zero).dx,
        entryBox.localToGlobal(Offset.zero).dy,
        entryBox.size.width,
        entryBox.size.height,
      );
    }

    // BASELINE (before any reflow): ancestor-owned Ink IS painted and aligned.
    final yellowBefore = await _paintedYellowBounds(tester, boundaryKey);
    expect(
      yellowBefore,
      isNotNull,
      reason: 'baseline: yellow background must be painted',
    );
    final entryBefore = entryRect();
    expect(
      yellowBefore!.top,
      closeTo(entryBefore.top, 3.0),
      reason:
          'baseline: painted yellow must align with the entry before reflow',
    );

    // Async reflow: the preceding context card grows; the entry moves DOWN.
    height.value = 200.0;
    await tester.pumpAndSettle();

    final yellowAfter = await _paintedYellowBounds(tester, boundaryKey);
    final entryAfter = entryRect();
    expect(
      yellowAfter,
      isNotNull,
      reason: 'post-reflow: yellow background must still be painted',
    );
    expect(
      yellowAfter!.top,
      closeTo(entryAfter.top, 3.0),
      reason:
          'painted yellow top (${yellowAfter.top}) must match the entry top '
          '(${entryAfter.top}) after async reflow; a mismatch after a valid '
          'aligned baseline is the stale InkDecoration offset (r3)',
    );
    // Unmount the tree before any disposal sanity so expectations cannot be
    // evaluated pre-unmount (harness hygiene).
    await tester.pumpWidget(const SizedBox.shrink());
    height.dispose();
  });
}
