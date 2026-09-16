import 'package:flutter_test/flutter_test.dart';
import 'package:yokonex_ems_game/features/waveforms/waveform_catalog.dart';

void main() {
  test('加载专用渐强波形和参考项目的 16 个经典 EMS 波形', () {
    expect(WaveformCatalog.presets, hasLength(17));
    expect(
      WaveformCatalog.presets.map((item) => item.name),
      containsAll(<String>['平缓渐强（0.5秒）', '呼吸', '潮汐', '连击', '挑逗2']),
    );
  });

  test('专用渐强波形每轮 0.5 秒且频率和脉宽平缓上升', () {
    final waveform = WaveformCatalog.smoothRamp;
    expect(waveform.durationMs, 500);
    expect(waveform.steps.map((step) => step.frequency), <int>[
      14,
      15,
      16,
      18,
      20,
    ]);
    for (var index = 1; index < waveform.steps.length; index++) {
      expect(
        waveform.steps[index].frequency,
        greaterThanOrEqualTo(waveform.steps[index - 1].frequency),
      );
      expect(
        waveform.steps[index].pulseWidth,
        greaterThan(waveform.steps[index - 1].pulseWidth),
      );
    }
  });

  test('经典波形只包含频率和脉冲数据', () {
    for (final waveform in WaveformCatalog.presets) {
      expect(waveform.steps, isNotEmpty);
      expect(
        waveform.steps.every(
          (step) => step.frequency >= 0 && step.frequency <= 100,
        ),
        isTrue,
      );
      expect(
        waveform.steps.every(
          (step) => step.pulseWidth >= 0 && step.pulseWidth <= 100,
        ),
        isTrue,
      );
    }
  });
}
