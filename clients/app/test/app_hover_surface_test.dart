import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowenssh/ui/app_hover_surface.dart';

void main() {
  testWidgets('悬停动画不移动按钮命中区域且点击只触发一次', (tester) async {
    final surfaceKey = GlobalKey();
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 40,
            child: AppHoverSurface(
              key: surfaceKey,
              onTap: () => tapCount++,
              hoverColor: Colors.grey,
              child: const Center(child: Text('测试按钮')),
            ),
          ),
        ),
      ),
    );

    final beforeHover = tester.getRect(find.byKey(surfaceKey));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(beforeHover.center);
    await tester.pump(const Duration(milliseconds: 180));

    expect(tester.getRect(find.byKey(surfaceKey)), beforeHover);

    await mouse.down(beforeHover.center);
    await mouse.up();
    expect(tapCount, 1);
  });

  testWidgets('进入和移开时颜色都保持单向变化且没有阴影', (tester) async {
    final surfaceKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 40,
            child: AppHoverSurface(
              key: surfaceKey,
              onTap: () {},
              color: Colors.white,
              hoverColor: Colors.black,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    BoxDecoration decoration() {
      final decoratedBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(surfaceKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      return decoratedBox.decoration as BoxDecoration;
    }

    final rect = tester.getRect(find.byKey(surfaceKey));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(rect.center);

    final entering = <double>[];
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      entering.add(decoration().color!.computeLuminance());
      expect(decoration().boxShadow, isNull);
    }
    expect(_isMonotonic(entering, increasing: false), isTrue);

    await mouse.moveTo(Offset.zero);
    final leaving = <double>[];
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      leaving.add(decoration().color!.computeLuminance());
      expect(decoration().boxShadow, isNull);
    }
    expect(_isMonotonic(leaving, increasing: true), isTrue);
  });
}

bool _isMonotonic(List<double> values, {required bool increasing}) {
  for (var i = 1; i < values.length; i++) {
    if (increasing && values[i] < values[i - 1]) return false;
    if (!increasing && values[i] > values[i - 1]) return false;
  }
  return true;
}
