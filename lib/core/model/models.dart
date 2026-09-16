import 'dart:convert';

import 'package:crypto/crypto.dart';

const int emsMaximumStrength = 180;
const String smoothRampWaveformId = 'game-smooth-ramp-500ms';

enum DeviceProtocol { emsV1, emsV2 }

extension DeviceProtocolX on DeviceProtocol {
  String get label => this == DeviceProtocol.emsV1 ? '电击器一代' : '电击器二代';

  String get wireName => this == DeviceProtocol.emsV1 ? 'EMS_V1' : 'EMS_V2';

  static DeviceProtocol? detect(String name) {
    final normalized = name.trim().toUpperCase();
    if (normalized.startsWith('YYC-DJ-V2')) return DeviceProtocol.emsV2;
    if (normalized.startsWith('YYC-DJ')) return DeviceProtocol.emsV1;
    return null;
  }

  static DeviceProtocol fromWireName(String value) => switch (value) {
    'EMS_V1' => DeviceProtocol.emsV1,
    'EMS_V2' => DeviceProtocol.emsV2,
    _ => throw FormatException('未知设备协议：$value'),
  };
}

enum ChannelSelection { a, b, ab }

extension ChannelSelectionX on ChannelSelection {
  String get label => switch (this) {
    ChannelSelection.a => 'A 通道',
    ChannelSelection.b => 'B 通道',
    ChannelSelection.ab => 'AB 通道',
  };

  int get protocolValue => switch (this) {
    ChannelSelection.a => 0x01,
    ChannelSelection.b => 0x02,
    ChannelSelection.ab => 0x03,
  };

  bool get includesA => this != ChannelSelection.b;
  bool get includesB => this != ChannelSelection.a;
}

enum ConnectionPhase { disconnected, scanning, connecting, connected, failed }

enum ElectrodeState { unknown, detached, discharging, attachedIdle }

extension ElectrodeStateX on ElectrodeState {
  String get label => switch (this) {
    ElectrodeState.unknown => '未知',
    ElectrodeState.detached => '未接入',
    ElectrodeState.discharging => '放电中',
    ElectrodeState.attachedIdle => '已接入',
  };
}

class WaveformStep {
  const WaveformStep({
    required this.durationMs,
    required this.frequency,
    required this.pulseWidth,
  });

  final int durationMs;
  final int frequency;
  final int pulseWidth;

  Map<String, Object?> toJson() => <String, Object?>{
    'durationMs': durationMs,
    'frequency': frequency,
    'pulseWidth': pulseWidth,
  };

  factory WaveformStep.fromJson(Map<String, Object?> value) => WaveformStep(
    durationMs: value['durationMs'] as int,
    frequency: value['frequency'] as int,
    pulseWidth: value['pulseWidth'] as int,
  );
}

class EmsWaveform {
  const EmsWaveform({
    required this.id,
    required this.name,
    required this.steps,
    this.custom = false,
  });

  final String id;
  final String name;
  final List<WaveformStep> steps;
  final bool custom;

  int get durationMs => steps.fold(0, (sum, step) => sum + step.durationMs);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'custom': custom,
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  factory EmsWaveform.fromJson(Map<String, Object?> value) => EmsWaveform(
    id: value['id'] as String,
    name: value['name'] as String,
    custom: value['custom'] as bool? ?? false,
    steps: (value['steps'] as List<Object?>)
        .map(
          (step) =>
              WaveformStep.fromJson((step as Map).cast<String, Object?>()),
        )
        .toList(growable: false),
  );
}

class ChannelGameConfig {
  const ChannelGameConfig({
    required this.startStrength,
    required this.maxStrength,
    required this.increaseEverySeconds,
    required this.increaseBy,
    required this.waveformId,
  });

  final int startStrength;
  final int maxStrength;
  final int increaseEverySeconds;
  final int increaseBy;
  final String waveformId;

  void validate() {
    if (startStrength < 0 || startStrength > maxStrength) {
      throw ArgumentError('起始强度不能大于最高强度');
    }
    if (maxStrength > emsMaximumStrength) {
      throw ArgumentError('最高强度不能超过协议上限 $emsMaximumStrength');
    }
    if (increaseEverySeconds <= 0 || increaseBy <= 0) {
      throw ArgumentError('自动加强度的间隔和增量必须大于 0');
    }
    if (waveformId.trim().isEmpty) throw ArgumentError('请选择波形');
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'startStrength': startStrength,
    'maxStrength': maxStrength,
    'increaseEverySeconds': increaseEverySeconds,
    'increaseBy': increaseBy,
    'waveformId': waveformId,
  };
}

class EmsGameConfig {
  const EmsGameConfig({
    required this.challengerName,
    required this.deviceId,
    required this.protocol,
    required this.channels,
    required this.durationSeconds,
    required this.channelA,
    required this.channelB,
    required this.channelsLinked,
  });

  final String challengerName;
  final String deviceId;
  final DeviceProtocol protocol;
  final ChannelSelection channels;
  final int durationSeconds;
  final ChannelGameConfig channelA;
  final ChannelGameConfig channelB;
  final bool channelsLinked;

  EmsGameConfig copyWith({String? challengerName}) => EmsGameConfig(
    challengerName: challengerName ?? this.challengerName,
    deviceId: deviceId,
    protocol: protocol,
    channels: channels,
    durationSeconds: durationSeconds,
    channelA: channelA,
    channelB: channelB,
    channelsLinked: channelsLinked,
  );

  void validate() {
    if (challengerName.trim().isEmpty || challengerName.trim().length > 30) {
      throw ArgumentError('挑战者名称需要 1 到 30 个字符');
    }
    if (durationSeconds < 5 || durationSeconds > 7200) {
      throw ArgumentError('游戏时长需要 5 秒到 120 分钟');
    }
    if (channels.includesA) channelA.validate();
    if (channels.includesB) channelB.validate();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'challengerName': challengerName.trim(),
    'deviceId': deviceId,
    'protocol': protocol.wireName,
    'channels': channels.name,
    'durationSeconds': durationSeconds,
    'channelA': channelA.toJson(),
    'channelB': channelB.toJson(),
    'channelsLinked': channelsLinked,
    'successRule': 'COMPLETE_DURATION',
  };

  String get fingerprint {
    final value = <String, Object?>{...toJson()}
      ..remove('challengerName')
      ..remove('deviceId');
    return sha256.convert(utf8.encode(jsonEncode(value))).toString();
  }
}

enum GameStatus {
  ready,
  countdown,
  running,
  stopping,
  success,
  failed,
  aborted,
  error,
}

enum ChallengeResult { success, failed, aborted }

extension ChallengeResultX on ChallengeResult {
  String get label => switch (this) {
    ChallengeResult.success => '成功',
    ChallengeResult.failed => '失败',
    ChallengeResult.aborted => '中止',
  };
}

class DeviceTelemetry {
  const DeviceTelemetry({
    this.batteryPercent,
    this.batteryUpdatedAt,
    this.reportedStrengthA = 0,
    this.reportedStrengthB = 0,
    this.electrodeA = ElectrodeState.unknown,
    this.electrodeB = ElectrodeState.unknown,
    this.channelAEnabled = false,
    this.channelBEnabled = false,
    this.lastError = '',
  });

  final int? batteryPercent;
  final DateTime? batteryUpdatedAt;
  final int reportedStrengthA;
  final int reportedStrengthB;
  final ElectrodeState electrodeA;
  final ElectrodeState electrodeB;
  final bool channelAEnabled;
  final bool channelBEnabled;
  final String lastError;

  bool get batteryLow => batteryPercent != null && batteryPercent! < 20;
  bool get batteryStale =>
      batteryUpdatedAt == null ||
      DateTime.now().difference(batteryUpdatedAt!).inSeconds >= 10;

  DeviceTelemetry copyWith({
    int? batteryPercent,
    DateTime? batteryUpdatedAt,
    int? reportedStrengthA,
    int? reportedStrengthB,
    ElectrodeState? electrodeA,
    ElectrodeState? electrodeB,
    bool? channelAEnabled,
    bool? channelBEnabled,
    String? lastError,
  }) => DeviceTelemetry(
    batteryPercent: batteryPercent ?? this.batteryPercent,
    batteryUpdatedAt: batteryUpdatedAt ?? this.batteryUpdatedAt,
    reportedStrengthA: reportedStrengthA ?? this.reportedStrengthA,
    reportedStrengthB: reportedStrengthB ?? this.reportedStrengthB,
    electrodeA: electrodeA ?? this.electrodeA,
    electrodeB: electrodeB ?? this.electrodeB,
    channelAEnabled: channelAEnabled ?? this.channelAEnabled,
    channelBEnabled: channelBEnabled ?? this.channelBEnabled,
    lastError: lastError ?? this.lastError,
  );
}

class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.advertisedServices,
    this.protocol,
  });

  final String id;
  final String name;
  final int rssi;
  final Set<String> advertisedServices;
  final DeviceProtocol? protocol;

  DiscoveredDevice copyWith({DeviceProtocol? protocol, int? rssi}) =>
      DiscoveredDevice(
        id: id,
        name: name,
        rssi: rssi ?? this.rssi,
        advertisedServices: advertisedServices,
        protocol: protocol ?? this.protocol,
      );
}

class ChallengeRecord {
  const ChallengeRecord({
    required this.id,
    required this.challengerName,
    required this.configFingerprint,
    required this.configJson,
    required this.protocol,
    required this.channels,
    required this.result,
    required this.elapsedMs,
    required this.maximumStrengthA,
    required this.maximumStrengthB,
    required this.finalStrengthA,
    required this.finalStrengthB,
    required this.startedAt,
    required this.finishedAt,
    this.batteryAtStart,
    this.batteryAtEnd,
  });

  final String id;
  final String challengerName;
  final String configFingerprint;
  final String configJson;
  final DeviceProtocol protocol;
  final ChannelSelection channels;
  final ChallengeResult result;
  final int elapsedMs;
  final int maximumStrengthA;
  final int maximumStrengthB;
  final int finalStrengthA;
  final int finalStrengthB;
  final int? batteryAtStart;
  final int? batteryAtEnd;
  final DateTime startedAt;
  final DateTime finishedAt;

  Map<String, Object?> toDatabase() => <String, Object?>{
    'id': id,
    'challenger_name': challengerName,
    'config_fingerprint': configFingerprint,
    'config_json': configJson,
    'protocol': protocol.wireName,
    'channels': channels.name,
    'result': result.name,
    'elapsed_ms': elapsedMs,
    'max_strength_a': maximumStrengthA,
    'max_strength_b': maximumStrengthB,
    'final_strength_a': finalStrengthA,
    'final_strength_b': finalStrengthB,
    'battery_start': batteryAtStart,
    'battery_end': batteryAtEnd,
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt.toIso8601String(),
  };

  factory ChallengeRecord.fromDatabase(Map<String, Object?> value) =>
      ChallengeRecord(
        id: value['id'] as String,
        challengerName: value['challenger_name'] as String,
        configFingerprint: value['config_fingerprint'] as String,
        configJson: value['config_json'] as String,
        protocol: DeviceProtocolX.fromWireName(value['protocol'] as String),
        channels: ChannelSelection.values.byName(value['channels'] as String),
        result: ChallengeResult.values.byName(value['result'] as String),
        elapsedMs: value['elapsed_ms'] as int,
        maximumStrengthA: value['max_strength_a'] as int,
        maximumStrengthB: value['max_strength_b'] as int,
        finalStrengthA: value['final_strength_a'] as int,
        finalStrengthB: value['final_strength_b'] as int,
        batteryAtStart: value['battery_start'] as int?,
        batteryAtEnd: value['battery_end'] as int?,
        startedAt: DateTime.parse(value['started_at'] as String),
        finishedAt: DateTime.parse(value['finished_at'] as String),
      );
}
