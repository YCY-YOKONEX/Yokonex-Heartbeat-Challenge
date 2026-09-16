import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/core/platform/ble_adapter.dart';
import 'package:yokonex_ems_game/core/platform/countdown_voice.dart';
import 'package:yokonex_ems_game/core/platform/universal_ble_adapter.dart';
import 'package:yokonex_ems_game/core/protocol/ems_protocol.dart';
import 'package:yokonex_ems_game/core/storage/app_database.dart';
import 'package:yokonex_ems_game/features/game/game_engine.dart';
import 'package:yokonex_ems_game/features/game/game_preset.dart';
import 'package:yokonex_ems_game/features/waveforms/waveform_catalog.dart';

final bleAdapterProvider = Provider<BleAdapter>((ref) => UniversalBleAdapter());
final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
final countdownVoicePlayerProvider = Provider<CountdownVoicePlayer>((ref) {
  final player = AssetCountdownVoicePlayer();
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});
final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

enum DeviceGameRole { arena, couple }

extension DeviceGameRoleX on DeviceGameRole {
  String get label => switch (this) {
    DeviceGameRole.arena => '竞技挑战',
    DeviceGameRole.couple => '情侣小游戏',
  };
}

class ConnectedDeviceState {
  const ConnectedDeviceState({
    required this.id,
    required this.name,
    required this.protocol,
    this.gameRole = DeviceGameRole.arena,
    this.telemetry = const DeviceTelemetry(),
  });

  final String id;
  final String name;
  final DeviceProtocol protocol;
  final DeviceGameRole gameRole;
  final DeviceTelemetry telemetry;

  ConnectedDeviceState copyWith({
    DeviceGameRole? gameRole,
    DeviceTelemetry? telemetry,
  }) => ConnectedDeviceState(
    id: id,
    name: name,
    protocol: protocol,
    gameRole: gameRole ?? this.gameRole,
    telemetry: telemetry ?? this.telemetry,
  );
}

class GameSessionState {
  const GameSessionState({
    required this.config,
    this.status = GameStatus.ready,
    this.countdownSeconds = 0,
    this.elapsedMs = 0,
    this.targetStrengthA = 0,
    this.targetStrengthB = 0,
    this.maximumStrengthA = 0,
    this.maximumStrengthB = 0,
    this.message = '',
    this.error = '',
  });

  final EmsGameConfig config;
  final GameStatus status;
  final int countdownSeconds;
  final int elapsedMs;
  final int targetStrengthA;
  final int targetStrengthB;
  final int maximumStrengthA;
  final int maximumStrengthB;
  final String message;
  final String error;

  bool get active =>
      status == GameStatus.countdown ||
      status == GameStatus.running ||
      status == GameStatus.stopping;

  GameSessionState copyWith({
    EmsGameConfig? config,
    GameStatus? status,
    int? countdownSeconds,
    int? elapsedMs,
    int? targetStrengthA,
    int? targetStrengthB,
    int? maximumStrengthA,
    int? maximumStrengthB,
    String? message,
    String? error,
  }) => GameSessionState(
    config: config ?? this.config,
    status: status ?? this.status,
    countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    targetStrengthA: targetStrengthA ?? this.targetStrengthA,
    targetStrengthB: targetStrengthB ?? this.targetStrengthB,
    maximumStrengthA: maximumStrengthA ?? this.maximumStrengthA,
    maximumStrengthB: maximumStrengthB ?? this.maximumStrengthB,
    message: message ?? this.message,
    error: error ?? this.error,
  );
}

const Object _unset = Object();

class AppState {
  const AppState({
    this.initialized = false,
    this.availability = BleAvailability.unknown,
    this.isScanning = false,
    this.discovered = const <String, DiscoveredDevice>{},
    this.connectingDeviceIds = const <String>{},
    this.devices = const <String, ConnectedDeviceState>{},
    this.sessions = const <String, GameSessionState>{},
    this.relayModeActive = false,
    this.leaderboardRevision = 0,
    this.liveDisplayRevision = 0,
    this.waveforms = const <EmsWaveform>[],
    this.records = const <ChallengeRecord>[],
    this.lastRecord,
    this.message = '',
    this.error = '',
  });

  final bool initialized;
  final BleAvailability availability;
  final bool isScanning;
  final Map<String, DiscoveredDevice> discovered;
  final Set<String> connectingDeviceIds;
  final Map<String, ConnectedDeviceState> devices;
  final Map<String, GameSessionState> sessions;
  final bool relayModeActive;
  final int leaderboardRevision;
  final int liveDisplayRevision;
  final List<EmsWaveform> waveforms;
  final List<ChallengeRecord> records;
  final ChallengeRecord? lastRecord;
  final String message;
  final String error;

  bool get gameActive =>
      relayModeActive || sessions.values.any((session) => session.active);
  bool get relayWaitingForPlayers =>
      relayModeActive &&
      sessions.isNotEmpty &&
      sessions.values.every((session) => session.status == GameStatus.ready);
  Iterable<GameSessionState> get activeSessions =>
      sessions.values.where((session) => session.active);
  String? get activeRelayDeviceId {
    for (final session in sessions.values) {
      if (session.active) return session.config.deviceId;
    }
    return null;
  }

  AppState copyWith({
    bool? initialized,
    BleAvailability? availability,
    bool? isScanning,
    Map<String, DiscoveredDevice>? discovered,
    Set<String>? connectingDeviceIds,
    Map<String, ConnectedDeviceState>? devices,
    Map<String, GameSessionState>? sessions,
    bool? relayModeActive,
    int? leaderboardRevision,
    int? liveDisplayRevision,
    List<EmsWaveform>? waveforms,
    List<ChallengeRecord>? records,
    Object? lastRecord = _unset,
    String? message,
    String? error,
  }) => AppState(
    initialized: initialized ?? this.initialized,
    availability: availability ?? this.availability,
    isScanning: isScanning ?? this.isScanning,
    discovered: discovered ?? this.discovered,
    connectingDeviceIds: connectingDeviceIds ?? this.connectingDeviceIds,
    devices: devices ?? this.devices,
    sessions: sessions ?? this.sessions,
    relayModeActive: relayModeActive ?? this.relayModeActive,
    leaderboardRevision: leaderboardRevision ?? this.leaderboardRevision,
    liveDisplayRevision: liveDisplayRevision ?? this.liveDisplayRevision,
    waveforms: waveforms ?? this.waveforms,
    records: records ?? this.records,
    lastRecord: identical(lastRecord, _unset)
        ? this.lastRecord
        : lastRecord as ChallengeRecord?,
    message: message ?? this.message,
    error: error ?? this.error,
  );
}

class _DeviceRuntime {
  _DeviceRuntime({required this.writeWithResponse});

  final bool writeWithResponse;
  bool busy = false;
  DateTime lastSuccessfulControlAt = DateTime.now();
  DateTime lastStatusQueryAt = DateTime.fromMillisecondsSinceEpoch(0);
}

class _SessionRuntime {
  _SessionRuntime({required this.startedAt, required this.batteryAtStart});

  final DateTime startedAt;
  final int? batteryAtStart;
  final Stopwatch stopwatch = Stopwatch();
  bool busy = false;
  bool stopping = false;
  int lastSuccessfulFrameMs = 0;
  int lastStatusQueryMs = -2000;
}

class AppController extends Notifier<AppState> {
  late final BleAdapter _ble;
  late final AppDatabase _database;
  late final CountdownVoicePlayer _countdownVoicePlayer;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  final Map<String, _DeviceRuntime> _deviceRuntimes =
      <String, _DeviceRuntime>{};
  final Map<String, _SessionRuntime> _sessionRuntimes =
      <String, _SessionRuntime>{};
  final Map<String, bool> _relayArmed = <String, bool>{};
  final Set<String> _manualRelayCountdowns = <String>{};
  final Map<String, Timer> _relayCountdownTimers = <String, Timer>{};
  final Map<String, Timer> _relayResultTimers = <String, Timer>{};
  final Map<String, Timer> _relayReleasePollTimers = <String, Timer>{};
  final Set<String> _relayReleaseQueriesInFlight = <String>{};
  final Set<String> _relayTestStopsInFlight = <String>{};
  final Set<String> _experienceStartsInFlight = <String>{};
  final Set<String> _batteryQueriesInFlight = <String>{};
  String? _activeRelayDeviceId;
  int _nextChallengerNumber = 1;
  Timer? _gameTimer;
  Timer? _relayMonitorTimer;
  Timer? _batteryMonitorTimer;
  bool _relayPollInFlight = false;
  bool _experienceModeActive = false;

  @override
  AppState build() {
    _ble = ref.watch(bleAdapterProvider);
    _database = ref.watch(databaseProvider);
    _countdownVoicePlayer = ref.watch(countdownVoicePlayerProvider);
    _subscriptions
      ..add(
        _ble.availabilityChanges.listen(
          (value) => state = state.copyWith(availability: value),
        ),
      )
      ..add(_ble.scanResults.listen(_onScanResult))
      ..add(_ble.connectionEvents.listen(_onConnectionEvent))
      ..add(_ble.notifications.listen(_onNotification));
    ref.onDispose(() {
      _gameTimer?.cancel();
      _relayMonitorTimer?.cancel();
      _batteryMonitorTimer?.cancel();
      for (final timer in _relayCountdownTimers.values) {
        timer.cancel();
      }
      for (final timer in _relayResultTimers.values) {
        timer.cancel();
      }
      for (final timer in _relayReleasePollTimers.values) {
        timer.cancel();
      }
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      unawaited(_ble.dispose());
      unawaited(_database.close());
    });
    unawaited(Future<void>.microtask(initialize));
    return const AppState();
  }

  Future<void> initialize() async {
    try {
      await _database.initialize();
      await _database.replaceBuiltInWaveforms(WaveformCatalog.presets);
      state = state.copyWith(
        initialized: true,
        waveforms: await _database.loadWaveforms(),
        records: await _database.loadChallenges(),
        availability: await _ble.getAvailability(),
      );
    } catch (error) {
      state = state.copyWith(initialized: true, error: '初始化失败：$error');
    }
  }

  Future<void> startScan() async {
    if (state.gameActive || state.isScanning) return;
    try {
      await _ble.requestPermissions();
      state = state.copyWith(
        isScanning: true,
        discovered: <String, DiscoveredDevice>{},
        error: '',
      );
      await _ble.startScan();
    } catch (error) {
      state = state.copyWith(isScanning: false, error: '扫描失败：$error');
    }
  }

  Future<void> stopScan() async {
    await _ble.stopScan();
    state = state.copyWith(isScanning: false);
  }

  Future<void> _onScanResult(BleScanResult result) async {
    final advertised = result.advertisedServiceUuids
        .map((value) => value.toLowerCase())
        .toSet();
    if (!advertised.contains(UniversalBleAdapter.serviceUuid) &&
        !result.name.toUpperCase().startsWith('YYC-DJ')) {
      return;
    }
    final remembered = await _database.protocolFor(result.deviceId);
    final device = DiscoveredDevice(
      id: result.deviceId,
      name: result.name.trim().isEmpty ? '未命名电击器' : result.name,
      rssi: result.rssi,
      advertisedServices: advertised,
      protocol: remembered ?? DeviceProtocolX.detect(result.name),
    );
    state = state.copyWith(
      discovered: <String, DiscoveredDevice>{
        ...state.discovered,
        device.id: device,
      },
    );
  }

  Future<void> connect(
    DiscoveredDevice device,
    DeviceProtocol protocol, {
    DeviceGameRole gameRole = DeviceGameRole.arena,
  }) async {
    if (state.gameActive ||
        state.devices.containsKey(device.id) ||
        state.connectingDeviceIds.contains(device.id)) {
      return;
    }
    final connecting = <String>{...state.connectingDeviceIds, device.id};
    state = state.copyWith(
      connectingDeviceIds: connecting,
      error: '',
      message: '正在连接 ${device.name}',
    );
    try {
      if (state.isScanning) await stopScan();
      await _ble.connect(device.id);
      final services = await _ble.discoverServices(device.id);
      final service = services
          .where(
            (item) =>
                item.uuid.toLowerCase() == UniversalBleAdapter.serviceUuid,
          )
          .toList();
      if (service.length != 1) throw StateError('设备缺少 FF30 服务');
      final write = service.single.characteristics
          .where(
            (item) => item.uuid.toLowerCase() == UniversalBleAdapter.writeUuid,
          )
          .toList();
      final notify = service.single.characteristics
          .where(
            (item) => item.uuid.toLowerCase() == UniversalBleAdapter.notifyUuid,
          )
          .toList();
      if (write.length != 1 || notify.length != 1) {
        throw StateError('设备缺少 FF31/FF32 特征');
      }
      await _ble.subscribe(device.id);
      _deviceRuntimes[device.id] = _DeviceRuntime(
        writeWithResponse:
            !write.single.writeWithoutResponse &&
            write.single.writeWithResponse,
      );
      await _database.saveProtocol(device.id, protocol);
      state = state.copyWith(
        connectingDeviceIds: <String>{...state.connectingDeviceIds}
          ..remove(device.id),
        devices: <String, ConnectedDeviceState>{
          ...state.devices,
          device.id: ConnectedDeviceState(
            id: device.id,
            name: device.name,
            protocol: protocol,
            gameRole: gameRole,
          ),
        },
        message: '已连接 ${device.name}',
      );
      await _write(device.id, EmsPacketEncoder.stop(protocol));
      await queryTelemetry(device.id);
      _startBatteryMonitoring();
    } catch (error) {
      _deviceRuntimes.remove(device.id);
      unawaited(_ble.disconnect(device.id));
      state = state.copyWith(
        connectingDeviceIds: <String>{...state.connectingDeviceIds}
          ..remove(device.id),
        devices: <String, ConnectedDeviceState>{...state.devices}
          ..remove(device.id),
        error: '连接失败：$error',
      );
    }
  }

  Future<void> disconnect(String deviceId) async {
    final device = state.devices[deviceId];
    if (device == null) return;
    final activeIds = state.sessions.entries
        .where(
          (entry) =>
              entry.value.active && entry.value.config.deviceId == deviceId,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    if (activeIds.isEmpty) {
      await _sendStopPackets(deviceId);
    } else {
      for (final sessionId in activeIds) {
        await stopSession(sessionId, ChallengeResult.aborted, reason: '设备已断开');
      }
    }
    await _ble.disconnect(deviceId);
    _deviceRuntimes.remove(deviceId);
    state = state.copyWith(
      devices: <String, ConnectedDeviceState>{...state.devices}
        ..remove(deviceId),
      message: '${device.name} 已断开',
    );
    if (state.devices.isEmpty) _stopBatteryMonitoring();
  }

  void setDeviceGameRole(String deviceId, DeviceGameRole role) {
    if (state.gameActive) return;
    _updateDevice(deviceId, (device) => device.copyWith(gameRole: role));
    state = state.copyWith(
      message: '${state.devices[deviceId]?.name}职责已设为${role.label}',
    );
  }

  Future<void> queryBattery(String deviceId) async {
    if (!state.devices.containsKey(deviceId) ||
        !_batteryQueriesInFlight.add(deviceId)) {
      return;
    }
    try {
      await _write(deviceId, EmsPacketEncoder.batteryQuery());
    } finally {
      _batteryQueriesInFlight.remove(deviceId);
    }
  }

  Future<void> queryChannelStatus(String deviceId) async {
    if (!state.devices.containsKey(deviceId)) return;
    await _write(deviceId, EmsPacketEncoder.channelQuery(ChannelSelection.a));
    // 无响应写入连续过快时部分设备会漏包，给 A/B 查询留出处理时间。
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await _write(deviceId, EmsPacketEncoder.channelQuery(ChannelSelection.b));
  }

  Future<void> queryTelemetry(String deviceId) async {
    if (!state.devices.containsKey(deviceId)) return;
    await queryBattery(deviceId);
    await queryChannelStatus(deviceId);
  }

  Future<void> saveWaveform(EmsWaveform waveform) async {
    if (waveform.name.trim().isEmpty || waveform.steps.isEmpty) {
      throw ArgumentError('波形名称和步骤不能为空');
    }
    for (final step in waveform.steps) {
      final invalidRest = step.frequency == 0 && step.pulseWidth != 0;
      if (step.durationMs < 100 ||
          step.durationMs > 60000 ||
          step.frequency < 0 ||
          step.frequency > 100 ||
          step.pulseWidth < 0 ||
          step.pulseWidth > 100 ||
          invalidRest) {
        throw ArgumentError('波形步骤参数超出范围');
      }
    }
    await _database.saveWaveform(waveform);
    state = state.copyWith(
      waveforms: await _database.loadWaveforms(),
      message: '波形已保存',
    );
  }

  Future<void> startDefaultRelay() async {
    if (state.devices.isEmpty) throw StateError('请先在设置中连接电击器');
    final preset = GamePresetStore.builtIns.firstWhere(
      (item) => item.id == GamePresetStore.defaultPresetId,
    );
    if (!state.waveforms.any((item) => item.id == preset.waveformId)) {
      throw StateError('默认平缓渐强波形尚未加载');
    }
    final channelConfig = ChannelGameConfig(
      startStrength: preset.startStrength,
      maxStrength: preset.maxStrength,
      increaseEverySeconds: preset.increaseEverySeconds,
      increaseBy: preset.increaseBy,
      waveformId: preset.waveformId,
    );

    final devices = state.devices.values.toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));
    final configs = <EmsGameConfig>[];
    // 所有已连接设备共用默认配置，每台设备创建独立的 A/B 等待位。
    for (final device in devices) {
      for (final channel in <ChannelSelection>[
        ChannelSelection.a,
        ChannelSelection.b,
      ]) {
        configs.add(
          EmsGameConfig(
            challengerName: '${channel.label}等待位',
            deviceId: device.id,
            protocol: device.protocol,
            channels: channel,
            durationSeconds: preset.durationSeconds,
            channelA: channelConfig,
            channelB: channelConfig,
            channelsLinked: false,
          ),
        );
      }
    }
    await startRelay(configs);
  }

  Future<void> startRelay(
    List<EmsGameConfig> configs, {
    bool experienceMode = false,
  }) async {
    if (configs.isEmpty || configs.length.isOdd) {
      throw ArgumentError('每台设备必须同时配置 A、B 两个通道');
    }
    if (state.gameActive) throw StateError('已有挑战或自动检测正在进行');
    final configsByDevice = <String, List<EmsGameConfig>>{};
    for (final config in configs) {
      configsByDevice.putIfAbsent(config.deviceId, () => []).add(config);
    }
    for (final deviceConfigs in configsByDevice.values) {
      if (deviceConfigs.length != 2 ||
          !deviceConfigs.any(
            (config) => config.channels == ChannelSelection.a,
          ) ||
          !deviceConfigs.any(
            (config) => config.channels == ChannelSelection.b,
          )) {
        throw ArgumentError('每台设备必须分别配置 A、B 通道');
      }
    }
    final sessionKeys = configs.map(_sessionKey).toSet();
    if (sessionKeys.length != configs.length) {
      throw ArgumentError('同一设备的同一通道只能配置一名玩家');
    }
    final referencesByRole = <DeviceGameRole, EmsGameConfig>{};
    for (final config in configs) {
      config.validate();
      if (config.channels == ChannelSelection.ab) {
        throw ArgumentError('双通道擂台需要分别配置 A、B 玩家');
      }
      final device = state.devices[config.deviceId];
      if (device == null) throw StateError('${config.challengerName} 的设备未连接');
      if (device.protocol != config.protocol) {
        throw StateError('${config.challengerName} 的设备协议不一致');
      }
      final reference = referencesByRole.putIfAbsent(
        device.gameRole,
        () => config,
      );
      final referenceChannel = reference.channels == ChannelSelection.a
          ? reference.channelA
          : reference.channelB;
      final channel = config.channels == ChannelSelection.a
          ? config.channelA
          : config.channelB;
      // 每种游戏内部仍保持统一参数，不同游戏可以使用各自配置。
      if (config.durationSeconds != reference.durationSeconds ||
          jsonEncode(channel.toJson()) !=
              jsonEncode(referenceChannel.toJson())) {
        throw ArgumentError('同一种游戏的所有设备和通道必须使用统一配置');
      }
    }

    _stopRelayMonitoring();
    _experienceModeActive = experienceMode;
    _activeRelayDeviceId = null;
    _nextChallengerNumber = 1;
    final sessions = <String, GameSessionState>{};
    for (final config in configs) {
      final key = _sessionKey(config);
      final waitingConfig = _waitingConfig(config);
      sessions[key] = GameSessionState(
        config: waitingConfig,
        status: GameStatus.ready,
        message: '等待${waitingConfig.channels.label}电极接入',
      );
      // 初次启用允许已接入的电极直接开始；每局结束后必须重新断开再接入。
      _relayArmed[key] = true;
    }
    state = state.copyWith(
      sessions: sessions,
      relayModeActive: true,
      lastRecord: null,
      error: '',
      message: '${configsByDevice.length} 台设备已启动，正在检测 A/B 电极',
    );
    // 先启动循环检测，首次查询卡住或丢包时仍能继续重试。
    _relayMonitorTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pollRelayDevices()),
    );
    for (final deviceId in configs.map((config) => config.deviceId).toSet()) {
      _evaluateRelayDevice(deviceId);
    }
    unawaited(_pollRelayDevices());
  }

  Future<void> updateRelayConfigs(
    List<EmsGameConfig> configs, {
    bool? experienceMode,
  }) async {
    if (!state.relayModeActive || state.sessions.isEmpty) {
      throw StateError('当前没有可更新的游戏');
    }
    // 调整参数默认保留当前模式，避免预设匹配失败后丢失不限时状态。
    final nextExperienceMode = experienceMode ?? _experienceModeActive;
    final configsByKey = <String, EmsGameConfig>{};
    for (final config in configs) {
      final key = _sessionKey(config);
      if (configsByKey.containsKey(key)) {
        throw ArgumentError('同一设备的同一通道只能配置一次');
      }
      configsByKey[key] = config;
    }
    if (configsByKey.length != state.sessions.length ||
        !state.sessions.keys.every(configsByKey.containsKey)) {
      throw ArgumentError('运行中的设备和通道不能变更');
    }

    final referencesByRole = <DeviceGameRole, EmsGameConfig>{};
    for (final entry in configsByKey.entries) {
      final config = entry.value;
      config.validate();
      if (config.channels == ChannelSelection.ab) {
        throw ArgumentError('双通道擂台需要分别配置 A、B 玩家');
      }
      final device = state.devices[config.deviceId];
      if (device == null || device.protocol != config.protocol) {
        throw StateError('${config.challengerName} 的设备状态不一致');
      }
      final reference = referencesByRole.putIfAbsent(
        device.gameRole,
        () => config,
      );
      final referenceChannel = reference.channels == ChannelSelection.a
          ? reference.channelA
          : reference.channelB;
      final channel = config.channels == ChannelSelection.a
          ? config.channelA
          : config.channelB;
      // 运行中更新也按游戏分别校验，避免一个游戏的参数覆盖另一个游戏。
      if (config.durationSeconds != reference.durationSeconds ||
          jsonEncode(channel.toJson()) !=
              jsonEncode(referenceChannel.toJson())) {
        throw ArgumentError('同一种游戏的所有设备和通道必须使用统一配置');
      }
      final runtime = _sessionRuntimes[entry.key];
      // 心动体验模式不受时长限制，运行中可继续调整任意玩法参数。
      final unlimitedExperience =
          nextExperienceMode && device.gameRole == DeviceGameRole.couple;
      if (!unlimitedExperience &&
          runtime != null &&
          config.durationSeconds * 1000 <=
              runtime.stopwatch.elapsedMilliseconds) {
        throw ArgumentError('新时长必须大于当前已进行时间');
      }
    }

    final updatedSessions = <String, GameSessionState>{};
    for (final entry in state.sessions.entries) {
      final submitted = configsByKey[entry.key]!;
      // 只替换玩法参数，保留当前玩家、计时、状态和最高强度记录。
      final updatedConfig = submitted.copyWith(
        challengerName: entry.value.config.challengerName,
      );
      updatedSessions[entry.key] = entry.value.copyWith(config: updatedConfig);
    }
    _experienceModeActive = nextExperienceMode;
    state = state.copyWith(
      sessions: updatedSessions,
      error: '',
      message: '运行中配置已更新',
    );
  }

  void startRelaySessionManually(String sessionId) {
    if (!state.relayModeActive) return;
    final session = state.sessions[sessionId];
    if (session == null || session.status != GameStatus.ready) return;
    if (!state.devices.containsKey(session.config.deviceId)) return;
    if (_activeRelayDeviceId != null &&
        _activeRelayDeviceId != session.config.deviceId) {
      return;
    }
    final device = state.devices[session.config.deviceId];
    final anotherChannelActive = state.sessions.values.any(
      (other) =>
          other.config.deviceId == session.config.deviceId && other.active,
    );
    if (device?.gameRole == DeviceGameRole.couple && anotherChannelActive) {
      return;
    }

    // 手动开始用于设备状态上报不及时的场景，倒计时期间不依赖电极检测结果。
    _activeRelayDeviceId ??= session.config.deviceId;
    _startRelayCountdown(sessionId, requireElectrode: false);
  }

  void _startRelayCountdown(String sessionId, {bool requireElectrode = true}) {
    final session = state.sessions[sessionId];
    if (session == null || session.status != GameStatus.ready) return;
    final device = state.devices[session.config.deviceId];
    if (device == null) return;
    if (requireElectrode) {
      _manualRelayCountdowns.remove(sessionId);
    } else {
      _manualRelayCountdowns.add(sessionId);
    }
    _stopRelayReleasePolling(sessionId);
    // 按实际接入顺序分配玩家序号，A/B 共用同一个连续计数器。
    final runningConfig = session.config.copyWith(
      challengerName: '玩家${_nextChallengerNumber++}',
    );
    _relayResultTimers.remove(sessionId)?.cancel();
    _relayCountdownTimers.remove(sessionId)?.cancel();
    if (_experienceModeActive && device.gameRole == DeviceGameRole.couple) {
      _startExperienceSession(
        sessionId,
        runningConfig,
        requireElectrode: requireElectrode,
      );
      return;
    }
    _updateSession(
      sessionId,
      (_) => GameSessionState(
        config: runningConfig,
        status: GameStatus.countdown,
        countdownSeconds: 3,
        message: '${runningConfig.channels.label}已接入，准备开始',
      ),
    );
    _relayArmed[sessionId] = false;
    state = state.copyWith(
      liveDisplayRevision: state.liveDisplayRevision + 1,
      message: '${runningConfig.challengerName} 已接入，3 秒后开始',
    );
    unawaited(_playCountdownCue(sessionId, CountdownVoiceCue.three));
    _relayCountdownTimers[sessionId] = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        final current = state.sessions[sessionId];
        if (current == null || current.status != GameStatus.countdown) {
          timer.cancel();
          _relayCountdownTimers.remove(sessionId);
          return;
        }
        final currentDevice = state.devices[current.config.deviceId];
        final electrode = current.config.channels == ChannelSelection.a
            ? currentDevice?.telemetry.electrodeA
            : currentDevice?.telemetry.electrodeB;
        final connected =
            electrode == ElectrodeState.attachedIdle ||
            electrode == ElectrodeState.discharging;
        if (!connected && !_manualRelayCountdowns.contains(sessionId)) {
          _cancelRelayCountdown(sessionId);
          return;
        }
        if (current.countdownSeconds > 1) {
          final nextSeconds = current.countdownSeconds - 1;
          _updateSession(
            sessionId,
            (value) => value.copyWith(countdownSeconds: nextSeconds),
          );
          unawaited(
            _playCountdownCue(
              sessionId,
              nextSeconds == 2 ? CountdownVoiceCue.two : CountdownVoiceCue.one,
            ),
          );
          return;
        }
        timer.cancel();
        _relayCountdownTimers.remove(sessionId);
        unawaited(_beginRelaySessionAfterVoice(sessionId));
      },
    );
  }

  void _startExperienceSession(
    String sessionId,
    EmsGameConfig runningConfig, {
    required bool requireElectrode,
  }) {
    if (!_experienceStartsInFlight.add(sessionId)) return;
    _updateSession(
      sessionId,
      (_) => GameSessionState(
        config: runningConfig,
        status: GameStatus.ready,
        message: '心动挑战正在启动',
      ),
    );
    _relayArmed[sessionId] = false;
    state = state.copyWith(
      liveDisplayRevision: state.liveDisplayRevision + 1,
      message: '${runningConfig.challengerName} 心动挑战正在启动',
    );
    unawaited(
      _beginExperienceSession(sessionId, requireElectrode: requireElectrode),
    );
  }

  Future<void> _beginExperienceSession(
    String sessionId, {
    required bool requireElectrode,
  }) async {
    try {
      await _stopRelayTestBeforeSession(sessionId, allowReady: true);
      final session = state.sessions[sessionId];
      if (!_experienceModeActive ||
          session == null ||
          session.status != GameStatus.ready) {
        return;
      }
      if (requireElectrode) {
        final device = state.devices[session.config.deviceId];
        final electrode = session.config.channels == ChannelSelection.a
            ? device?.telemetry.electrodeA
            : device?.telemetry.electrodeB;
        final connected =
            electrode == ElectrodeState.attachedIdle ||
            electrode == ElectrodeState.discharging;
        if (!connected) {
          _updateSession(
            sessionId,
            (value) => GameSessionState(
              config: _waitingConfig(value.config),
              status: GameStatus.ready,
              message: '电极已断开，等待${value.config.channels.label}重新接入',
            ),
          );
          _relayArmed[sessionId] = true;
          _releaseRelayDeviceIfIdle(session.config.deviceId);
          return;
        }
      }
      _beginRelaySession(sessionId, allowReady: true);
    } finally {
      _experienceStartsInFlight.remove(sessionId);
    }
  }

  Future<void> _beginRelaySessionAfterVoice(String sessionId) async {
    await _playCountdownCue(sessionId, CountdownVoiceCue.go);
    await _stopRelayTestBeforeSession(sessionId);
    _beginRelaySession(sessionId);
  }

  Future<void> _stopRelayTestBeforeSession(
    String sessionId, {
    bool allowReady = false,
  }) async {
    if (!_relayTestStopsInFlight.add(sessionId)) return;
    try {
      final session = state.sessions[sessionId];
      if (session == null ||
          (session.status != GameStatus.countdown &&
              !(allowReady && session.status == GameStatus.ready))) {
        return;
      }
      // 倒计时结束后先关闭细微测试电流，再切换到正式游戏输出。
      await _write(
        session.config.deviceId,
        _relayTestPacket(session.config, enabled: false),
      );
    } catch (error) {
      state = state.copyWith(error: '停止通道测试失败：$error');
    } finally {
      _relayTestStopsInFlight.remove(sessionId);
    }
  }

  Future<void> _playCountdownCue(
    String sessionId,
    CountdownVoiceCue cue,
  ) async {
    try {
      await _countdownVoicePlayer.play(sessionId, cue);
    } on Object {
      // 语音播放失败不能阻断倒计时和设备安全控制。
    }
  }

  Future<void> _stopCountdownVoice(String sessionId) async {
    try {
      await _countdownVoicePlayer.stop(sessionId);
    } on Object {
      // 停止语音失败不影响设备归零流程。
    }
  }

  void _beginRelaySession(String sessionId, {bool allowReady = false}) {
    final session = state.sessions[sessionId];
    if (session == null ||
        (session.status != GameStatus.countdown &&
            !(allowReady && session.status == GameStatus.ready))) {
      return;
    }
    final device = state.devices[session.config.deviceId];
    if (device == null) return;
    _manualRelayCountdowns.remove(sessionId);
    _sessionRuntimes[sessionId] = _SessionRuntime(
      startedAt: DateTime.now(),
      batteryAtStart: device.telemetry.batteryPercent,
    )..stopwatch.start();
    _deviceRuntimes[device.id]?.lastSuccessfulControlAt = DateTime.now();
    _updateSession(
      sessionId,
      (value) => GameSessionState(
        config: value.config,
        status: GameStatus.running,
        countdownSeconds: 0,
        message: '${value.config.channels.label}已接入，挑战开始',
      ),
    );
    state = state.copyWith(message: '${session.config.challengerName} 挑战开始');
    _ensureGameTimer();
  }

  void _cancelRelayCountdown(String sessionId) {
    _relayCountdownTimers.remove(sessionId)?.cancel();
    _manualRelayCountdowns.remove(sessionId);
    unawaited(_stopCountdownVoice(sessionId));
    final session = state.sessions[sessionId];
    if (session == null || session.status != GameStatus.countdown) return;
    _updateSession(
      sessionId,
      (value) => GameSessionState(
        config: _waitingConfig(value.config),
        status: GameStatus.ready,
        message: '电极已断开，等待${value.config.channels.label}重新接入',
      ),
    );
    _relayArmed[sessionId] = true;
    _releaseRelayDeviceIfIdle(session.config.deviceId);
    _showLeaderboardIfAllSlotsWaiting();
  }

  void _ensureGameTimer() {
    if (_gameTimer?.isActive ?? false) return;
    _gameTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_tickAll()),
    );
  }

  Future<void> _tickAll() async {
    final deviceIds = state.sessions.entries
        .where((entry) => entry.value.status == GameStatus.running)
        .map((entry) => entry.value.config.deviceId)
        .toSet();
    if (deviceIds.isEmpty) {
      _gameTimer?.cancel();
      return;
    }
    await Future.wait(deviceIds.map(_tickDevice));
  }

  Future<void> _tickDevice(String deviceId) async {
    final deviceRuntime = _deviceRuntimes[deviceId];
    if (deviceRuntime == null || deviceRuntime.busy) return;
    deviceRuntime.busy = true;
    try {
      final waveforms = <String, EmsWaveform>{
        for (final item in state.waveforms) item.id: item,
      };
      final running = state.sessions.entries
          .where(
            (entry) =>
                entry.value.status == GameStatus.running &&
                entry.value.config.deviceId == deviceId,
          )
          .toList(growable: false);
      final outputs = <String, GameOutput>{};
      final completed = <String>[];
      // 情侣设备的心动体验持续运行，强度达到配置上限后保持不变。
      final unlimitedExperience =
          _experienceModeActive &&
          state.devices[deviceId]?.gameRole == DeviceGameRole.couple;
      for (final entry in running) {
        final runtime = _sessionRuntimes[entry.key];
        if (runtime == null) continue;
        final elapsedMs = runtime.stopwatch.elapsedMilliseconds;
        if (!unlimitedExperience &&
            elapsedMs >= entry.value.config.durationSeconds * 1000) {
          _updateSession(
            entry.key,
            (value) =>
                value.copyWith(elapsedMs: value.config.durationSeconds * 1000),
          );
          completed.add(entry.key);
          continue;
        }
        outputs[entry.key] = GameEngine.outputAt(
          config: entry.value.config,
          elapsedMs: elapsedMs,
          waveforms: waveforms,
        );
      }
      for (final sessionId in completed) {
        await stopSession(sessionId, ChallengeResult.success, reason: '挑战完成');
      }
      if (outputs.isNotEmpty) {
        await _sendDeviceOutputs(deviceId, outputs);
        deviceRuntime.lastSuccessfulControlAt = DateTime.now();
        for (final entry in outputs.entries) {
          final runtime = _sessionRuntimes[entry.key];
          if (runtime == null) continue;
          runtime.lastSuccessfulFrameMs = runtime.stopwatch.elapsedMilliseconds;
          _updateRunningSession(entry.key, entry.value);
        }
      }

      final now = DateTime.now();
      if (now.difference(deviceRuntime.lastStatusQueryAt).inMilliseconds >=
          2000) {
        deviceRuntime.lastStatusQueryAt = now;
        await _write(
          deviceId,
          EmsPacketEncoder.channelQuery(ChannelSelection.a),
        );
        await _write(
          deviceId,
          EmsPacketEncoder.channelQuery(ChannelSelection.b),
        );
      }
    } catch (error) {
      final silence = DateTime.now()
          .difference(deviceRuntime.lastSuccessfulControlAt)
          .inMilliseconds;
      if (silence >= 500) {
        try {
          await _sendStopPackets(deviceId, attempts: 1);
        } on Object {
          // 继续累计无有效控制帧的时间，由 1000ms 规则结束该挑战者。
        }
      }
      if (silence >= 1000) {
        final failedIds = state.sessions.entries
            .where(
              (entry) =>
                  entry.value.active && entry.value.config.deviceId == deviceId,
            )
            .map((entry) => entry.key)
            .toList(growable: false);
        for (final sessionId in failedIds) {
          await stopSession(
            sessionId,
            ChallengeResult.failed,
            reason: '控制发送异常：$error',
          );
        }
      }
    } finally {
      deviceRuntime.busy = false;
    }
  }

  Future<void> _sendDeviceOutputs(
    String deviceId,
    Map<String, GameOutput> outputs,
  ) async {
    final device = state.devices[deviceId];
    if (device == null) throw StateError('设备未连接');
    if (device.protocol == DeviceProtocol.emsV1) {
      for (final entry in outputs.entries) {
        final session = state.sessions[entry.key];
        // 通知和 100ms 控制帧可能同时到达，下发前再次确认该玩家仍在运行。
        if (session == null ||
            session.status != GameStatus.running ||
            !_sessionRuntimes.containsKey(entry.key)) {
          continue;
        }
        await _write(deviceId, _controlPacket(session.config, entry.value));
      }
      return;
    }
    var strengthA = 0;
    var frequencyA = 0;
    var pulseWidthA = 0;
    var strengthB = 0;
    var frequencyB = 0;
    var pulseWidthB = 0;
    for (final entry in outputs.entries) {
      final session = state.sessions[entry.key];
      if (session == null ||
          session.status != GameStatus.running ||
          !_sessionRuntimes.containsKey(entry.key)) {
        continue;
      }
      final output = entry.value;
      if (output.strengthA > 0) {
        strengthA = output.strengthA;
        frequencyA = output.waveformA.frequency;
        pulseWidthA = output.waveformA.pulseWidth;
      }
      if (output.strengthB > 0) {
        strengthB = output.strengthB;
        frequencyB = output.waveformB.frequency;
        pulseWidthB = output.waveformB.pulseWidth;
      }
    }
    await _write(
      deviceId,
      EmsPacketEncoder.v2Realtime(
        strengthA: strengthA,
        frequencyA: frequencyA,
        pulseWidthA: pulseWidthA,
        strengthB: strengthB,
        frequencyB: frequencyB,
        pulseWidthB: pulseWidthB,
      ),
    );
  }

  void _updateRunningSession(String sessionId, GameOutput output) {
    final runtime = _sessionRuntimes[sessionId];
    if (runtime == null) return;
    final elapsedMs = runtime.stopwatch.elapsedMilliseconds;
    _updateSession(sessionId, (current) {
      return current.copyWith(
        elapsedMs: elapsedMs,
        targetStrengthA: output.strengthA,
        targetStrengthB: output.strengthB,
        maximumStrengthA: output.strengthA > current.maximumStrengthA
            ? output.strengthA
            : current.maximumStrengthA,
        maximumStrengthB: output.strengthB > current.maximumStrengthB
            ? output.strengthB
            : current.maximumStrengthB,
      );
    });
  }

  Future<void> stopSession(
    String sessionId,
    ChallengeResult result, {
    required String reason,
  }) async {
    unawaited(_stopCountdownVoice(sessionId));
    final runtime = _sessionRuntimes[sessionId];
    final existing = state.sessions[sessionId];
    if (existing?.status == GameStatus.countdown && runtime == null) {
      _relayCountdownTimers.remove(sessionId)?.cancel();
      _manualRelayCountdowns.remove(sessionId);
      if (state.relayModeActive) {
        _updateSession(
          sessionId,
          (value) => GameSessionState(
            config: _waitingConfig(value.config),
            status: GameStatus.ready,
            message: reason,
          ),
        );
        _relayArmed[sessionId] = true;
        _releaseRelayDeviceIfIdle(existing!.config.deviceId);
        _showLeaderboardIfAllSlotsWaiting();
      } else {
        _updateSession(
          sessionId,
          (value) => value.copyWith(
            status: GameStatus.aborted,
            countdownSeconds: 0,
            message: reason,
          ),
        );
      }
      return;
    }
    if (runtime == null ||
        existing == null ||
        runtime.stopping ||
        !existing.active) {
      return;
    }
    runtime.stopping = true;
    runtime.stopwatch.stop();
    final elapsed = existing.status == GameStatus.countdown
        ? existing.elapsedMs
        : runtime.stopwatch.elapsedMilliseconds.clamp(
            0,
            existing.config.durationSeconds * 1000,
          );
    _updateSession(
      sessionId,
      (session) => session.copyWith(
        status: GameStatus.stopping,
        elapsedMs: elapsed,
        message: '正在停止${session.config.channels.label}',
      ),
    );
    final deviceId = existing.config.deviceId;
    String stopError = '';
    try {
      await _sendSessionStopPackets(sessionId);
      if (state.devices.containsKey(deviceId)) {
        await _write(
          deviceId,
          EmsPacketEncoder.channelQuery(ChannelSelection.a),
        );
        await _write(
          deviceId,
          EmsPacketEncoder.channelQuery(ChannelSelection.b),
        );
      }
    } catch (error) {
      stopError = '停止指令未确认，请立即操作设备本体：$error';
    }

    final session = state.sessions[sessionId]!;
    final now = DateTime.now();
    final device = state.devices[deviceId];
    final record = ChallengeRecord(
      id: '$sessionId-${now.microsecondsSinceEpoch}',
      challengerName: session.config.challengerName.trim(),
      configFingerprint: session.config.fingerprint,
      configJson: jsonEncode(session.config.toJson()),
      protocol: session.config.protocol,
      channels: session.config.channels,
      result: result,
      elapsedMs: session.elapsedMs,
      maximumStrengthA: session.maximumStrengthA,
      maximumStrengthB: session.maximumStrengthB,
      finalStrengthA: session.targetStrengthA,
      finalStrengthB: session.targetStrengthB,
      batteryAtStart: runtime.batteryAtStart,
      batteryAtEnd: device?.telemetry.batteryPercent,
      startedAt: runtime.startedAt,
      finishedAt: now,
    );
    try {
      await _database.saveChallenge(record);
    } catch (error) {
      stopError = stopError.isEmpty
          ? '挑战记录保存失败：$error'
          : '$stopError；记录保存失败：$error';
    }
    final records = await _database.loadChallenges();
    _updateSession(
      sessionId,
      (value) => value.copyWith(
        status: switch (result) {
          ChallengeResult.success => GameStatus.success,
          ChallengeResult.failed => GameStatus.failed,
          ChallengeResult.aborted => GameStatus.aborted,
        },
        targetStrengthA: 0,
        targetStrengthB: 0,
        message: reason,
        error: stopError,
      ),
    );
    _sessionRuntimes.remove(sessionId);
    state = state.copyWith(
      records: records,
      lastRecord: record,
      message: '${record.challengerName}：$reason',
      error: stopError.isEmpty ? state.error : stopError,
    );
    if (state.relayModeActive) {
      _scheduleRelayResult(sessionId);
      _releaseRelayDeviceIfIdle(deviceId);
    }
    _cleanupTimers();
  }

  Future<void> _sendSessionStopPackets(
    String sessionId, {
    int attempts = 3,
  }) async {
    final session = state.sessions[sessionId];
    if (session == null) return;
    final device = state.devices[session.config.deviceId];
    if (device == null) return;
    for (var index = 0; index < attempts; index++) {
      if (device.protocol == DeviceProtocol.emsV1) {
        await _write(
          device.id,
          EmsPacketEncoder.v1Control(
            channels: session.config.channels,
            enabled: false,
            strength: 0,
            mode: 0x11,
            frequency: 0,
            pulseWidth: 0,
          ),
        );
      } else {
        final remaining = _currentOutputsForDevice(
          device.id,
          excluding: sessionId,
        );
        if (remaining.isEmpty) {
          await _write(device.id, EmsPacketEncoder.stop(device.protocol));
        } else {
          await _sendDeviceOutputs(device.id, remaining);
        }
      }
      if (index + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Map<String, GameOutput> _currentOutputsForDevice(
    String deviceId, {
    String? excluding,
  }) {
    final waveforms = <String, EmsWaveform>{
      for (final item in state.waveforms) item.id: item,
    };
    final outputs = <String, GameOutput>{};
    for (final entry in state.sessions.entries) {
      if (entry.key == excluding ||
          entry.value.status != GameStatus.running ||
          entry.value.config.deviceId != deviceId) {
        continue;
      }
      final runtime = _sessionRuntimes[entry.key];
      if (runtime == null) continue;
      outputs[entry.key] = GameEngine.outputAt(
        config: entry.value.config,
        elapsedMs: runtime.stopwatch.elapsedMilliseconds,
        waveforms: waveforms,
      );
    }
    return outputs;
  }

  void _scheduleRelayResult(String sessionId) {
    _relayResultTimers.remove(sessionId)?.cancel();
    _startRelayReleasePolling(sessionId);
    _relayResultTimers[sessionId] = Timer(const Duration(seconds: 10), () {
      _relayResultTimers.remove(sessionId);
      if (!state.relayModeActive) return;
      final completed = state.sessions[sessionId];
      if (completed == null || completed.active) return;
      _updateSession(
        sessionId,
        (value) => GameSessionState(
          config: _waitingConfig(value.config),
          status: GameStatus.ready,
          message: '等待${value.config.channels.label}电极重新接入',
        ),
      );
      _evaluateRelayDevice(completed.config.deviceId);
      _showLeaderboardIfAllSlotsWaiting(otherwiseMessage: '本轮结果已进入排行榜');
    });
  }

  void _startRelayReleasePolling(String sessionId) {
    _stopRelayReleasePolling(sessionId);
    // 结算期间提高当前通道的查询频率，避免快速拔插被常规一秒轮询漏掉。
    _relayReleasePollTimers[sessionId] = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => unawaited(_pollRelayRelease(sessionId)),
    );
    unawaited(_pollRelayRelease(sessionId));
  }

  Future<void> _pollRelayRelease(String sessionId) async {
    if (!state.relayModeActive || (_relayArmed[sessionId] ?? false)) {
      _stopRelayReleasePolling(sessionId);
      return;
    }
    final session = state.sessions[sessionId];
    if (session == null || session.active) {
      _stopRelayReleasePolling(sessionId);
      return;
    }
    final deviceRuntime = _deviceRuntimes[session.config.deviceId];
    if (deviceRuntime == null) {
      _stopRelayReleasePolling(sessionId);
      return;
    }
    if (deviceRuntime.busy || !_relayReleaseQueriesInFlight.add(sessionId)) {
      return;
    }
    try {
      await _write(
        session.config.deviceId,
        EmsPacketEncoder.channelQuery(session.config.channels),
      );
    } on Object {
      // 常规自动检测仍会继续执行，单次快速查询失败不打断挑战流程。
    } finally {
      _relayReleaseQueriesInFlight.remove(sessionId);
    }
  }

  void _stopRelayReleasePolling(String sessionId) {
    _relayReleasePollTimers.remove(sessionId)?.cancel();
    _relayReleaseQueriesInFlight.remove(sessionId);
  }

  void _showLeaderboardIfAllSlotsWaiting({String? otherwiseMessage}) {
    if (!state.relayModeActive) return;
    // 两张卡都完成结算并回到等待状态后，才切换到排行榜。
    final allSlotsWaiting =
        state.sessions.isNotEmpty &&
        state.sessions.values.every(
          (session) => session.status == GameStatus.ready,
        );
    state = state.copyWith(
      leaderboardRevision: allSlotsWaiting
          ? state.leaderboardRevision + 1
          : state.leaderboardRevision,
      message: allSlotsWaiting
          ? '当前无人挑战，展示排行榜'
          : otherwiseMessage ?? state.message,
    );
  }

  Future<void> stopAll({
    ChallengeResult result = ChallengeResult.aborted,
    String reason = '全部挑战已停止',
  }) async {
    final relayWasActive = state.relayModeActive;
    if (relayWasActive) {
      _stopRelayMonitoring();
      state = state.copyWith(relayModeActive: false);
    }
    final ids = state.sessions.entries
        .where((entry) => entry.value.active)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final sessionId in ids) {
      await stopSession(sessionId, result, reason: reason);
    }
    if (relayWasActive) {
      for (final deviceId in state.devices.keys) {
        await _sendStopPackets(deviceId);
      }
      state = state.copyWith(message: reason);
    }
  }

  Future<void> emergencyStop() async {
    if (state.gameActive) {
      await stopAll(reason: '用户紧急停止');
      return;
    }
    for (final deviceId in state.devices.keys) {
      await _sendStopPackets(deviceId);
    }
  }

  Future<void> handleAppBackground() async {
    if (state.gameActive) {
      await stopAll(result: ChallengeResult.failed, reason: '应用进入后台，已停止输出');
    }
  }

  void clearFinishedSessions() {
    if (state.relayModeActive) return;
    state = state.copyWith(
      sessions: <String, GameSessionState>{
        for (final entry in state.sessions.entries)
          if (entry.value.active) entry.key: entry.value,
      },
    );
  }

  Future<void> clearRecords() async {
    await _database.clearChallenges();
    state = state.copyWith(records: <ChallengeRecord>[], message: '排行榜已清空');
  }

  Uint8List _controlPacket(EmsGameConfig config, GameOutput output) {
    if (config.protocol == DeviceProtocol.emsV1) {
      final useB = config.channels == ChannelSelection.b;
      final strength = useB ? output.strengthB : output.strengthA;
      final waveform = useB ? output.waveformB : output.waveformA;
      return EmsPacketEncoder.v1Control(
        channels: config.channels,
        enabled: strength > 0,
        strength: strength,
        mode: 0x11,
        frequency: waveform.frequency,
        pulseWidth: waveform.pulseWidth,
      );
    }
    return EmsPacketEncoder.v2Realtime(
      strengthA: output.strengthA,
      frequencyA: output.strengthA > 0 ? output.waveformA.frequency : 0,
      pulseWidthA: output.strengthA > 0 ? output.waveformA.pulseWidth : 0,
      strengthB: output.strengthB,
      frequencyB: output.strengthB > 0 ? output.waveformB.frequency : 0,
      pulseWidthB: output.strengthB > 0 ? output.waveformB.pulseWidth : 0,
    );
  }

  Future<void> _sendStopPackets(String deviceId, {int attempts = 3}) async {
    final device = state.devices[deviceId];
    if (device == null) return;
    for (var index = 0; index < attempts; index++) {
      await _write(deviceId, EmsPacketEncoder.stop(device.protocol));
      if (index + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<void> _write(String deviceId, Uint8List value) async {
    final runtime = _deviceRuntimes[deviceId];
    if (runtime == null || !state.devices.containsKey(deviceId)) {
      throw StateError('设备未连接');
    }
    await _ble.write(deviceId, value, withResponse: runtime.writeWithResponse);
  }

  void _onConnectionEvent(BleConnectionEvent event) {
    switch (event.phase) {
      case BleConnectionPhase.connecting:
        state = state.copyWith(
          connectingDeviceIds: <String>{
            ...state.connectingDeviceIds,
            event.deviceId,
          },
        );
      case BleConnectionPhase.connected:
        break;
      case BleConnectionPhase.disconnected:
        final device = state.devices[event.deviceId];
        if (device == null) return;
        _deviceRuntimes.remove(event.deviceId);
        _batteryQueriesInFlight.remove(event.deviceId);
        state = state.copyWith(
          devices: <String, ConnectedDeviceState>{...state.devices}
            ..remove(event.deviceId),
          error: '${device.name} 连接中断',
        );
        if (state.devices.isEmpty) _stopBatteryMonitoring();
        final activeIds = state.sessions.entries
            .where(
              (entry) =>
                  entry.value.active &&
                  entry.value.config.deviceId == event.deviceId,
            )
            .map((entry) => entry.key)
            .toList(growable: false);
        for (final sessionId in activeIds) {
          unawaited(
            stopSession(sessionId, ChallengeResult.failed, reason: '设备连接中断'),
          );
        }
      case BleConnectionPhase.failed:
        state = state.copyWith(
          connectingDeviceIds: <String>{...state.connectingDeviceIds}
            ..remove(event.deviceId),
          error: event.message,
        );
    }
  }

  void _onNotification(BleNotification notification) {
    final device = state.devices[notification.deviceId];
    if (device == null) return;
    try {
      final decoded = EmsPacketDecoder.decode(notification.value);
      switch (decoded) {
        case BatteryNotification value:
          _updateDevice(
            notification.deviceId,
            (current) => current.copyWith(
              telemetry: current.telemetry.copyWith(
                batteryPercent: value.percent,
                batteryUpdatedAt: DateTime.now(),
              ),
            ),
          );
        case ChannelStatusNotification value:
          final isA = value.channel == ChannelSelection.a;
          _updateDevice(
            notification.deviceId,
            (current) => current.copyWith(
              telemetry: current.telemetry.copyWith(
                reportedStrengthA: isA ? value.strength : null,
                reportedStrengthB: isA ? null : value.strength,
                electrodeA: isA ? value.electrode : null,
                electrodeB: isA ? null : value.electrode,
                channelAEnabled: isA ? value.enabled : null,
                channelBEnabled: isA ? null : value.enabled,
              ),
            ),
          );
          final affected = state.sessions.entries.where(
            (entry) =>
                entry.value.status == GameStatus.running &&
                entry.value.config.deviceId == notification.deviceId &&
                (isA
                    ? entry.value.config.channels.includesA
                    : entry.value.config.channels.includesB),
          );
          if (value.electrode == ElectrodeState.detached) {
            for (final entry in affected.toList(growable: false)) {
              unawaited(
                stopSession(
                  entry.key,
                  ChallengeResult.failed,
                  reason: '${value.channel.label}电极已脱落',
                ),
              );
            }
          }
          _evaluateRelayDevice(notification.deviceId);
        case DeviceErrorNotification value:
          _updateDevice(
            notification.deviceId,
            (current) => current.copyWith(
              telemetry: current.telemetry.copyWith(lastError: value.message),
            ),
          );
          state = state.copyWith(error: '${device.name}：${value.message}');
          final activeIds = state.sessions.entries
              .where(
                (entry) =>
                    entry.value.status == GameStatus.running &&
                    entry.value.config.deviceId == notification.deviceId,
              )
              .map((entry) => entry.key)
              .toList(growable: false);
          for (final sessionId in activeIds) {
            unawaited(
              stopSession(
                sessionId,
                ChallengeResult.failed,
                reason: value.message,
              ),
            );
          }
        case UnknownNotification():
          break;
      }
    } catch (error) {
      state = state.copyWith(error: '${device.name} 通知解析失败：$error');
    }
  }

  Future<void> _pollRelayDevices() async {
    if (!state.relayModeActive || _relayPollInFlight) return;
    _relayPollInFlight = true;
    final deviceIds = state.sessions.values
        .map((session) => session.config.deviceId)
        .toSet();
    try {
      for (final deviceId in deviceIds) {
        if (!state.devices.containsKey(deviceId)) continue;
        try {
          final sessionIds = state.sessions.entries
              .where((entry) => entry.value.config.deviceId == deviceId)
              .map((entry) => entry.key)
              .toList(growable: false);
          for (final sessionId in sessionIds) {
            if (!state.relayModeActive) return;
            await _pollRelayChannel(
              sessionId,
            ).timeout(const Duration(seconds: 2));
          }
        } catch (error) {
          state = state.copyWith(error: '自动检测通道失败：$error');
        }
        _evaluateRelayDevice(deviceId);
      }
    } finally {
      _relayPollInFlight = false;
    }
  }

  Future<void> _pollRelayChannel(String sessionId) async {
    final session = state.sessions[sessionId];
    if (session == null ||
        !state.relayModeActive ||
        !state.devices.containsKey(session.config.deviceId) ||
        _relayTestStopsInFlight.contains(sessionId)) {
      return;
    }
    final testingCircuit =
        (session.status == GameStatus.ready &&
            (_relayArmed[sessionId] ?? false)) ||
        (session.status == GameStatus.countdown &&
            !_manualRelayCountdowns.contains(sessionId));
    if (testingCircuit) {
      // 等待接入和倒计时期间持续发送最小强度，用实际电流确认回路仍然存在。
      await _write(
        session.config.deviceId,
        _relayTestPacket(session.config, enabled: true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (!state.relayModeActive ||
        !state.devices.containsKey(session.config.deviceId) ||
        _relayTestStopsInFlight.contains(sessionId)) {
      return;
    }
    await _write(
      session.config.deviceId,
      EmsPacketEncoder.channelQuery(session.config.channels),
    );
  }

  Uint8List _relayTestPacket(EmsGameConfig config, {required bool enabled}) {
    if (config.protocol == DeviceProtocol.emsV1) {
      return EmsPacketEncoder.v1Control(
        channels: config.channels,
        enabled: enabled,
        strength: enabled ? 1 : 0,
        mode: 0x11,
        frequency: enabled ? 17 : 0,
        pulseWidth: enabled ? 1 : 0,
      );
    }
    return EmsPacketEncoder.v2Frequency(
      channel: config.channels,
      strength: enabled ? 1 : 0,
      points: const <({int frequency, int pulseWidth})>[
        (frequency: 17, pulseWidth: 1),
      ],
    );
  }

  void _startBatteryMonitoring() {
    _batteryMonitorTimer?.cancel();
    // 电量独立于通道状态刷新，避免自动检测时重复发送整套查询。
    _batteryMonitorTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollConnectedBatteries()),
    );
  }

  void _stopBatteryMonitoring() {
    _batteryMonitorTimer?.cancel();
    _batteryMonitorTimer = null;
    _batteryQueriesInFlight.clear();
  }

  Future<void> _pollConnectedBatteries() async {
    for (final deviceId in state.devices.keys.toList(growable: false)) {
      try {
        await queryBattery(deviceId);
      } catch (error) {
        state = state.copyWith(error: '电量实时刷新失败：$error');
      }
    }
  }

  void _evaluateRelayDevice(String deviceId) {
    if (!state.relayModeActive) return;
    if (_activeRelayDeviceId != null && _activeRelayDeviceId != deviceId) {
      return;
    }
    final device = state.devices[deviceId];
    if (device == null) return;
    final candidates = state.sessions.entries
        .where(
          (entry) =>
              entry.value.config.deviceId == deviceId &&
              entry.value.config.channels != ChannelSelection.ab,
        )
        .toList(growable: false);
    var coupleChannelClaimed =
        device.gameRole == DeviceGameRole.couple &&
        candidates.any((entry) => entry.value.active);
    for (final entry in candidates) {
      final electrode = entry.value.config.channels == ChannelSelection.a
          ? device.telemetry.electrodeA
          : device.telemetry.electrodeB;
      final connected =
          electrode == ElectrodeState.attachedIdle ||
          electrode == ElectrodeState.discharging;
      if (!connected) {
        if (entry.value.status == GameStatus.countdown &&
            !_manualRelayCountdowns.contains(entry.key)) {
          _cancelRelayCountdown(entry.key);
        }
        _relayArmed[entry.key] = true;
        _stopRelayReleasePolling(entry.key);
        continue;
      }
      if (entry.value.status == GameStatus.ready &&
          (_relayArmed[entry.key] ?? false)) {
        if (coupleChannelClaimed) continue;
        // 不同设备互斥；取得执行权后，同一设备的 A/B 都可以独立开始。
        _activeRelayDeviceId ??= deviceId;
        _startRelayCountdown(entry.key);
        if (device.gameRole == DeviceGameRole.couple) {
          coupleChannelClaimed = true;
        }
      }
    }
  }

  void _releaseRelayDeviceIfIdle(String deviceId) {
    if (_activeRelayDeviceId != deviceId) return;
    final stillActive = state.sessions.values.any(
      (session) => session.config.deviceId == deviceId && session.active,
    );
    if (stillActive) return;
    _activeRelayDeviceId = null;
    // 当前设备结束后，立即检查其他已形成回路的设备。
    for (final waitingDeviceId in state.devices.keys) {
      _evaluateRelayDevice(waitingDeviceId);
      if (_activeRelayDeviceId != null) break;
    }
  }

  void _stopRelayMonitoring() {
    _relayMonitorTimer?.cancel();
    _relayMonitorTimer = null;
    _relayPollInFlight = false;
    for (final timer in _relayCountdownTimers.values) {
      timer.cancel();
    }
    _relayCountdownTimers.clear();
    _manualRelayCountdowns.clear();
    for (final timer in _relayResultTimers.values) {
      timer.cancel();
    }
    _relayResultTimers.clear();
    for (final timer in _relayReleasePollTimers.values) {
      timer.cancel();
    }
    _relayReleasePollTimers.clear();
    _relayReleaseQueriesInFlight.clear();
    _relayTestStopsInFlight.clear();
    _experienceStartsInFlight.clear();
    _relayArmed.clear();
    _activeRelayDeviceId = null;
    _experienceModeActive = false;
    unawaited(_countdownVoicePlayer.stopAll().catchError((_) {}));
  }

  String _sessionKey(EmsGameConfig config) =>
      config.channels == ChannelSelection.ab
      ? config.deviceId
      : '${config.deviceId}:${config.channels.name}';

  EmsGameConfig _waitingConfig(EmsGameConfig config) =>
      config.copyWith(challengerName: '${config.channels.label}等待位');

  void _updateDevice(
    String deviceId,
    ConnectedDeviceState Function(ConnectedDeviceState) update,
  ) {
    final current = state.devices[deviceId];
    if (current == null) return;
    state = state.copyWith(
      devices: <String, ConnectedDeviceState>{
        ...state.devices,
        deviceId: update(current),
      },
    );
  }

  void _updateSession(
    String sessionId,
    GameSessionState Function(GameSessionState) update,
  ) {
    final current = state.sessions[sessionId];
    if (current == null) return;
    state = state.copyWith(
      sessions: <String, GameSessionState>{
        ...state.sessions,
        sessionId: update(current),
      },
    );
  }

  void _cleanupTimers() {
    if (!state.sessions.values.any(
      (session) => session.status == GameStatus.running,
    )) {
      _gameTimer?.cancel();
    }
  }
}
