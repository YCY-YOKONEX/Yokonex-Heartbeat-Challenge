import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yokonex_ems_game/app/app_controller.dart';
import 'package:yokonex_ems_game/app/visual_style.dart';
import 'package:yokonex_ems_game/core/model/models.dart';
import 'package:yokonex_ems_game/core/platform/csv_export.dart';
import 'package:yokonex_ems_game/features/game/game_preset.dart';
import 'package:yokonex_ems_game/features/leaderboard/leaderboard.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int index = widget.initialIndex;

  void _selectDestination(int value) {
    if (value == 2) {
      context.go('/game');
      return;
    }
    setState(() => index = value);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    const pages = <Widget>[
      DevicePage(),
      GameSetupPage(),
      LiveDisplayEntryPage(),
      LeaderboardPage(),
    ];
    final content = SafeArea(
      child: Column(
        children: <Widget>[
          const _GlobalStatusBar(),
          Expanded(
            child: IndexedStack(index: index, children: pages),
          ),
        ],
      ),
    );
    return Scaffold(
      body: wide
          ? Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: _selectDestination,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      color: Theme.of(context).colorScheme.secondary,
                      child: const Text(
                        'EC',
                        style: TextStyle(
                          color: Color(0xff101310),
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.bluetooth_searching),
                      label: Text('设备'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.tune),
                      label: Text('挑战'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.monitor_heart),
                      label: Text('展示'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.leaderboard),
                      label: Text('排行'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: _selectDestination,
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.bluetooth_searching),
                  label: '设备',
                ),
                NavigationDestination(icon: Icon(Icons.tune), label: '挑战'),
                NavigationDestination(
                  icon: Icon(Icons.monitor_heart),
                  label: '展示',
                ),
                NavigationDestination(
                  icon: Icon(Icons.leaderboard),
                  label: '排行',
                ),
              ],
            ),
    );
  }
}

class _GlobalStatusBar extends ConsumerWidget {
  const _GlobalStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final activeCount = state.activeSessions.length;
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Material(
      color: state.error.isNotEmpty
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: <Widget>[
            const Icon(Icons.bolt),
            const SizedBox(width: 6),
            const Text(
              '电击挑战',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 12),
            GameVisualStyleSwitch(compact: compact),
            const Spacer(),
            if (!compact) ...<Widget>[
              const Icon(Icons.bluetooth_connected, size: 20),
              const SizedBox(width: 6),
              Text(state.devices.isEmpty ? '设备未连接' : '设备已连接'),
              const SizedBox(width: 14),
              Text(activeCount > 0 ? '$activeCount 名挑战者进行中' : '当前无挑战'),
              const SizedBox(width: 10),
            ],
            IconButton.filled(
              tooltip: '全部紧急停止',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: state.devices.isEmpty
                  ? null
                  : () => ref
                        .read(appControllerProvider.notifier)
                        .emergencyStop(),
              icon: const Icon(Icons.stop_circle),
            ),
          ],
        ),
      ),
    );
  }
}

class DevicePage extends ConsumerWidget {
  const DevicePage({super.key, this.fixedGameRole});

  final DeviceGameRole? fixedGameRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final connected = state.devices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final discovered = state.discovered.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return PageBody(
      title: '设备连接',
      actions: <Widget>[
        IconButton(
          tooltip: state.isScanning ? '停止扫描' : '扫描设备',
          onPressed: state.gameActive
              ? null
              : state.isScanning
              ? controller.stopScan
              : controller.startScan,
          icon: Icon(state.isScanning ? Icons.stop : Icons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          if (state.error.isNotEmpty)
            MessagePanel(text: state.error, error: true),
          if (state.message.isNotEmpty) MessagePanel(text: state.message),
          Text('已连接设备', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (connected.isEmpty)
            const _EmptyPanel(icon: Icons.bluetooth_disabled, text: '还没有连接电击器')
          else
            ...connected.map(
              (device) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.electrical_services, size: 30),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Wrap(
                            spacing: 24,
                            runSpacing: 8,
                            children: <Widget>[
                              Metric(label: '设备', value: device.name),
                              Metric(label: '协议', value: device.protocol.label),
                              Metric(
                                label: '职责',
                                value: (fixedGameRole ?? device.gameRole).label,
                              ),
                              Metric(
                                label: '电量',
                                value: _batteryText(device.telemetry),
                              ),
                              Metric(
                                label: 'A 电极',
                                value: device.telemetry.electrodeA.label,
                              ),
                              Metric(
                                label: 'B 电极',
                                value: device.telemetry.electrodeB.label,
                              ),
                            ],
                          ),
                        ),
                        if (fixedGameRole == null)
                          PopupMenuButton<DeviceGameRole>(
                            tooltip: '设置设备职责',
                            enabled: !state.gameActive,
                            initialValue: device.gameRole,
                            onSelected: (role) =>
                                controller.setDeviceGameRole(device.id, role),
                            itemBuilder: (context) => DeviceGameRole.values
                                .map(
                                  (role) => PopupMenuItem<DeviceGameRole>(
                                    value: role,
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          role == DeviceGameRole.arena
                                              ? Icons.sports_esports
                                              : Icons.favorite,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(role.label),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            icon: const Icon(Icons.assignment_ind_outlined),
                          )
                        else
                          const Tooltip(
                            message: '心动体验设备',
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.favorite),
                            ),
                          ),
                        IconButton(
                          tooltip: '刷新状态',
                          onPressed: () => controller.queryTelemetry(device.id),
                          icon: const Icon(Icons.sync),
                        ),
                        IconButton(
                          tooltip: '断开设备',
                          onPressed: state.gameActive
                              ? null
                              : () => controller.disconnect(device.id),
                          icon: const Icon(Icons.link_off),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          Text('附近设备', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (discovered.isEmpty)
            _EmptyPanel(
              icon: Icons.bluetooth_searching,
              text: state.isScanning ? '正在扫描电击器...' : '点击右上角开始扫描',
            )
          else
            ...discovered.map((device) {
              final isConnected = state.devices.containsKey(device.id);
              final isConnecting = state.connectingDeviceIds.contains(
                device.id,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(device.name),
                    subtitle: Text(
                      '${device.protocol?.label ?? '协议待选择'} · RSSI ${device.rssi}',
                    ),
                    trailing: FilledButton.icon(
                      onPressed: isConnected || isConnecting || state.gameActive
                          ? null
                          : () => _connectDevice(context, controller, device),
                      icon: Icon(isConnected ? Icons.check : Icons.link),
                      label: Text(
                        isConnected
                            ? '已连接'
                            : isConnecting
                            ? '连接中'
                            : '连接',
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _connectDevice(
    BuildContext context,
    AppController controller,
    DiscoveredDevice device,
  ) async {
    var protocol = device.protocol;
    protocol ??= await showDialog<DeviceProtocol>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择设备型号'),
        children: DeviceProtocol.values
            .map(
              (item) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(item.label),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (protocol != null) {
      await controller.connect(
        device,
        protocol,
        gameRole: fixedGameRole ?? DeviceGameRole.arena,
      );
    }
  }
}

class GameSetupPage extends ConsumerStatefulWidget {
  const GameSetupPage({
    super.key,
    this.initialPresetId,
    this.initialCategory = GamePresetCategory.endurance,
    this.experienceOnly = false,
  });

  final String? initialPresetId;
  final GamePresetCategory initialCategory;
  final bool experienceOnly;

  @override
  ConsumerState<GameSetupPage> createState() => _GameSetupPageState();
}

class _GameSetupPageState extends ConsumerState<GameSetupPage> {
  final Map<GamePresetCategory, _PlayerDraft> drafts =
      <GamePresetCategory, _PlayerDraft>{};
  final Map<GamePresetCategory, String?> selectedPresetIds =
      <GamePresetCategory, String?>{
        for (final category in GamePresetCategory.values)
          category: category.defaultPresetId,
      };
  List<GamePreset> presets = <GamePreset>[...GamePresetStore.builtIns];
  late GamePresetCategory selectedCategory;
  int configRevision = 0;

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appControllerProvider);
    final currentConfig = appState.sessions.values.firstOrNull?.config;
    final currentDevice = currentConfig == null
        ? null
        : appState.devices[currentConfig.deviceId];
    final requestedPresetId =
        widget.initialPresetId ?? widget.initialCategory.defaultPresetId;
    final requestedPreset = presets.firstWhereOrNull(
      (preset) => preset.id == requestedPresetId,
    );
    selectedCategory = widget.experienceOnly
        ? GamePresetCategory.heart
        : currentDevice != null
        ? _categoryForRole(currentDevice.gameRole)
        : requestedPreset?.category ?? widget.initialCategory;
    selectedPresetIds[selectedCategory] = currentConfig == null
        ? requestedPresetId
        : _matchingPresetId(
            currentConfig,
            _presetsForCategory(selectedCategory),
          );
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    final custom = await GamePresetStore.loadCustom();
    if (!mounted) return;
    setState(() {
      presets = <GamePreset>[...GamePresetStore.builtIns, ...custom];
      for (final category in GamePresetCategory.values) {
        final selectedId = selectedPresetIds[category];
        if (selectedId != null &&
            !presets.any(
              (preset) =>
                  preset.id == selectedId && preset.category == category,
            )) {
          selectedPresetIds[category] = category.defaultPresetId;
        }
      }
    });
  }

  List<GamePreset> _presetsForCategory(GamePresetCategory category) => presets
      .where((preset) => preset.category == category)
      .toList(growable: false);

  _PlayerDraft _draftFor(
    GamePresetCategory category,
    List<EmsWaveform> waveforms, {
    EmsGameConfig? currentConfig,
  }) => drafts.putIfAbsent(category, () {
    final draft = _PlayerDraft(waveformId: waveforms.firstOrNull?.id ?? '');
    if (currentConfig != null) {
      draft.applyConfig(currentConfig);
    } else {
      final selectedId =
          selectedPresetIds[category] ?? category.defaultPresetId;
      final preset = presets.firstWhereOrNull(
        (item) => item.id == selectedId && item.category == category,
      );
      if (preset != null) draft.applyPreset(preset, waveforms);
    }
    return draft;
  });

  EmsGameConfig? _currentConfigFor(
    GamePresetCategory category,
    AppState state,
  ) {
    if (!state.relayModeActive) return null;
    for (final session in state.sessions.values) {
      final device = state.devices[session.config.deviceId];
      if (device != null && _categoryForRole(device.gameRole) == category) {
        return session.config;
      }
    }
    return null;
  }

  GamePresetCategory _categoryForDevice(ConnectedDeviceState device) =>
      widget.experienceOnly
      ? GamePresetCategory.heart
      : _categoryForRole(device.gameRole);

  List<EmsGameConfig> _configsForDevices(
    List<ConnectedDeviceState> devices,
    AppState state,
  ) => <EmsGameConfig>[
    // 每台设备按照连接页设置的游戏职责读取对应草稿。
    for (final device in devices)
      ..._draftFor(
        _categoryForDevice(device),
        state.waveforms,
        currentConfig: _currentConfigFor(_categoryForDevice(device), state),
      ).toRelayConfigs(device),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final devices = state.devices.values.toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));
    final canUpdate = state.relayModeActive && state.sessions.isNotEmpty;
    final categoryPresets = _presetsForCategory(selectedCategory);
    final selectedPresetId = selectedPresetIds[selectedCategory];
    final categoryDevices = widget.experienceOnly
        ? devices
        : devices
              .where(
                (device) =>
                    _categoryForRole(device.gameRole) == selectedCategory,
              )
              .toList(growable: false);
    final draft = devices.isEmpty
        ? null
        : _draftFor(
            selectedCategory,
            state.waveforms,
            currentConfig: _currentConfigFor(selectedCategory, state),
          );
    return PageBody(
      title: widget.experienceOnly ? '心动体验设置' : '多设备挑战设置',
      actions: <Widget>[
        IconButton(
          tooltip: '新建自定义波形',
          onPressed: state.gameActive ? null : () => _createWaveform(context),
          icon: const Icon(Icons.add_chart),
        ),
      ],
      child: draft == null
          ? const _EmptyPanel(icon: Icons.electrical_services, text: '请先连接电击器')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: <Widget>[
                Text(
                  widget.experienceOnly
                      ? '所有设备共用心动配置。触摸接通后直接开始，只运行先接入的一路。'
                      : '每种游戏单独配置。设备会按连接页设置的职责自动使用对应参数。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (!widget.experienceOnly) ...<Widget>[
                  _GameCategorySelector(
                    value: selectedCategory,
                    enabled: !state.gameActive || canUpdate,
                    onChanged: (category) => setState(() {
                      selectedCategory = category;
                      configRevision++;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                _PresetToolbar(
                  presets: categoryPresets,
                  selectedId: selectedPresetId,
                  locked: state.gameActive && !canUpdate,
                  onSelected: (id) => _applyPreset(
                    draft,
                    state.waveforms,
                    selectedCategory,
                    id,
                  ),
                  onSave: () => _savePreset(context, draft, selectedCategory),
                  onDelete: () =>
                      _deleteSelectedPreset(context, selectedCategory),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RelayDeviceConfigCard(
                    key: ValueKey<String>(
                      '${selectedCategory.name}-${selectedPresetId ?? 'custom'}-$configRevision',
                    ),
                    category: selectedCategory,
                    devices: categoryDevices,
                    draft: draft,
                    waveforms: state.waveforms,
                    locked: state.gameActive && !canUpdate,
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(height: 4),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  onPressed: state.gameActive && !canUpdate
                      ? null
                      : () => canUpdate
                            ? _updateRelay(context, devices, state)
                            : _startRelay(context, devices, state),
                  icon: Icon(canUpdate ? Icons.sync : Icons.play_arrow),
                  label: Text(
                    canUpdate
                        ? '应用配置'
                        : widget.experienceOnly
                        ? '启动心动体验'
                        : '启动全部设备检测',
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _startRelay(
    BuildContext context,
    List<ConnectedDeviceState> devices,
    AppState state,
  ) async {
    try {
      if (widget.experienceOnly) {
        // 独立心动 App 固定情侣职责，确保自动接入和手动开始都直接进入体验。
        for (final device in devices) {
          ref
              .read(appControllerProvider.notifier)
              .setDeviceGameRole(device.id, DeviceGameRole.couple);
        }
      }
      final configs = _configsForDevices(devices, state);
      // 只有独立心动体验启用不限时直出；完整版中的情侣职责仍走挑战倒计时。
      final experienceMode = widget.experienceOnly;
      await ref
          .read(appControllerProvider.notifier)
          .startRelay(configs, experienceMode: experienceMode);
      if (!context.mounted) return;
      // 启动检测后先进入心动挑战，竞技设备接入后会自动切换页面。
      context.go('/couple-game');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _updateRelay(
    BuildContext context,
    List<ConnectedDeviceState> devices,
    AppState state,
  ) async {
    try {
      final configs = _configsForDevices(devices, state);
      await ref
          .read(appControllerProvider.notifier)
          .updateRelayConfigs(configs);
      if (!context.mounted) return;
      context.go('/couple-game');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _createWaveform(BuildContext context) async {
    final waveform = await showDialog<EmsWaveform>(
      context: context,
      builder: (context) => const _WaveformEditorDialog(),
    );
    if (waveform == null) return;
    try {
      await ref.read(appControllerProvider.notifier).saveWaveform(waveform);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  void _applyPreset(
    _PlayerDraft draft,
    List<EmsWaveform> waveforms,
    GamePresetCategory category,
    String id,
  ) {
    final preset = presets.firstWhereOrNull(
      (item) => item.id == id && item.category == category,
    );
    if (preset == null) return;
    setState(() {
      selectedPresetIds[category] = id;
      configRevision++;
      draft.applyPreset(preset, waveforms);
    });
  }

  Future<void> _savePreset(
    BuildContext context,
    _PlayerDraft draft,
    GamePresetCategory category,
  ) async {
    final name = await _askPresetName(context);
    if (name == null) return;
    try {
      final preset = draft.toPreset(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        category: category,
      );
      await GamePresetStore.save(preset);
      await _loadPresets();
      if (!mounted) return;
      setState(() => selectedPresetIds[category] = preset.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _deleteSelectedPreset(
    BuildContext context,
    GamePresetCategory category,
  ) async {
    final selectedId = selectedPresetIds[category];
    final selected = presets.firstWhereOrNull(
      (item) => item.id == selectedId && item.category == category,
    );
    if (selected == null || !selected.custom) return;
    await GamePresetStore.delete(selected.id);
    selectedPresetIds[category] = category.defaultPresetId;
    drafts.remove(category);
    await _loadPresets();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('自定义预设已删除')));
    }
  }

  Future<String?> _askPresetName(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存配置预设'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(labelText: '预设名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }
}

class _GameCategorySelector extends StatelessWidget {
  const _GameCategorySelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final GamePresetCategory value;
  final bool enabled;
  final ValueChanged<GamePresetCategory> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<GamePresetCategory>(
    key: const ValueKey<String>('game-config-category'),
    segments: const <ButtonSegment<GamePresetCategory>>[
      ButtonSegment<GamePresetCategory>(
        value: GamePresetCategory.endurance,
        icon: Icon(Icons.sports_esports),
        label: Text('耐久挑战'),
      ),
      ButtonSegment<GamePresetCategory>(
        value: GamePresetCategory.heart,
        icon: Icon(Icons.favorite),
        label: Text('心动挑战'),
      ),
    ],
    selected: <GamePresetCategory>{value},
    onSelectionChanged: enabled
        ? (selection) => onChanged(selection.single)
        : null,
  );
}

class _PresetToolbar extends StatelessWidget {
  const _PresetToolbar({
    required this.presets,
    required this.selectedId,
    required this.locked,
    required this.onSelected,
    required this.onSave,
    required this.onDelete,
  });

  final List<GamePreset> presets;
  final String? selectedId;
  final bool locked;
  final ValueChanged<String> onSelected;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final selected = presets.firstWhereOrNull((item) => item.id == selectedId);
    return Row(
      children: <Widget>[
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey<String?>(selected?.id),
            initialValue: selected?.id,
            decoration: const InputDecoration(
              labelText: '配置预设',
              prefixIcon: Icon(Icons.bookmarks),
            ),
            items: presets
                .map(
                  (preset) => DropdownMenuItem<String>(
                    value: preset.id,
                    child: Text(preset.name),
                  ),
                )
                .toList(),
            onChanged: locked
                ? null
                : (value) {
                    if (value != null) onSelected(value);
                  },
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '保存当前配置为预设',
          onPressed: locked ? null : onSave,
          icon: const Icon(Icons.save),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: '删除自定义预设',
          onPressed: locked || selected == null || !selected.custom
              ? null
              : onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

class _RelayDeviceConfigCard extends StatelessWidget {
  const _RelayDeviceConfigCard({
    super.key,
    required this.category,
    required this.devices,
    required this.draft,
    required this.waveforms,
    required this.locked,
    required this.onChanged,
  });

  final GamePresetCategory category;
  final List<ConnectedDeviceState> devices;
  final _PlayerDraft draft;
  final List<EmsWaveform> waveforms;
  final bool locked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.electrical_services),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${category.label} · ${devices.length} 台设备',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${devices.length * 2} 个通道'),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final device in devices)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${device.name} · ${device.protocol.label} · '
                    '${device.gameRole.label} · '
                    'A ${device.telemetry.electrodeA.label} · '
                    'B ${device.telemetry.electrodeB.label} · '
                    '电量 ${_batteryText(device.telemetry)}',
                  ),
                ),
            ],
          ),
          const Divider(height: 28),
          _UnifiedConfigEditor(
            duration: draft.duration,
            values: draft.values,
            waveforms: waveforms,
            enabled: !locked,
            onDurationChanged: (value) => draft.duration = value,
            onChanged: onChanged,
          ),
        ],
      ),
    ),
  );
}

class _UnifiedConfigEditor extends StatelessWidget {
  const _UnifiedConfigEditor({
    required this.duration,
    required this.values,
    required this.waveforms,
    required this.enabled,
    required this.onDurationChanged,
    required this.onChanged,
  });

  final String duration;
  final _ChannelDraft values;
  final List<EmsWaveform> waveforms;
  final bool enabled;
  final ValueChanged<String> onDurationChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        'A/B 通道统一规则',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 170,
            child: TextFormField(
              initialValue: duration,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '挑战时长（秒）'),
              onChanged: onDurationChanged,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _ChannelConfigPanel(
        label: '统一强度与波形',
        values: values,
        waveforms: waveforms,
        enabled: enabled,
        onChanged: onChanged,
      ),
    ],
  );
}

class _ChannelConfigPanel extends StatelessWidget {
  const _ChannelConfigPanel({
    required this.label,
    required this.values,
    required this.waveforms,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final _ChannelDraft values;
  final List<EmsWaveform> waveforms;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedId = waveforms.any((item) => item.id == values.waveformId)
        ? values.waveformId
        : waveforms.firstOrNull?.id;
    final selected = waveforms.firstWhereOrNull(
      (item) => item.id == selectedId,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text('强度规则', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _NumberInput(
                  label: '起始强度',
                  value: values.start,
                  enabled: enabled,
                  onChanged: (value) => values.start = value,
                ),
                _NumberInput(
                  label: '最高强度',
                  value: values.maximum,
                  enabled: enabled,
                  onChanged: (value) => values.maximum = value,
                ),
                _NumberInput(
                  label: '每隔 X 秒',
                  value: values.every,
                  enabled: enabled,
                  onChanged: (value) => values.every = value,
                ),
                _NumberInput(
                  label: '增加 N',
                  value: values.increaseBy,
                  enabled: enabled,
                  onChanged: (value) => values.increaseBy = value,
                ),
              ],
            ),
            const Divider(height: 28),
            Text('输出波形', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final picker = DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  decoration: const InputDecoration(labelText: '选择波形'),
                  items: waveforms
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: enabled
                      ? (value) {
                          if (value != null) {
                            values.waveformId = value;
                            onChanged();
                          }
                        }
                      : null,
                );
                final preview = SizedBox(
                  height: 76,
                  child: CustomPaint(
                    painter: _WaveformPreviewPainter(
                      selected,
                      frequencyColor: Theme.of(context).colorScheme.primary,
                      pulseColor: Theme.of(context).colorScheme.secondary,
                      gridColor: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
                return compact
                    ? Column(
                        children: <Widget>[
                          picker,
                          const SizedBox(height: 10),
                          preview,
                        ],
                      )
                    : Row(
                        children: <Widget>[
                          SizedBox(width: 240, child: picker),
                          const SizedBox(width: 16),
                          Expanded(child: preview),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberInput extends StatelessWidget {
  const _NumberInput({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 140,
    child: TextFormField(
      initialValue: value,
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    ),
  );
}

class LiveDisplayEntryPage extends ConsumerWidget {
  const LiveDisplayEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return PageBody(
      title: '实时展示',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.monitor_heart,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  state.sessions.isEmpty
                      ? '还没有挑战数据'
                      : '${state.sessions.length} 名挑战者可展示',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '展示页会实时显示每名挑战者的时间、强度、电量和可选波形。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: state.sessions.isEmpty
                      ? null
                      : () => context.go('/couple-game'),
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('打开独立展示页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key, this.onReturnToGame});

  final VoidCallback? onReturnToGame;

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollTimer;
  bool _gameRouteScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _scrollLeaderboard(),
    );
  }

  void _scrollLeaderboard() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    // 每次按当前可见区域翻一屏，最后一屏展示完成后再回到顶部。
    final next = position.pixels + position.viewportDimension;
    final atEnd = position.pixels >= position.maxScrollExtent - 1;
    final target = atEnd
        ? 0.0
        : next.clamp(0.0, position.maxScrollExtent).toDouble();
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
    );
  }

  void _scheduleGameRoute() {
    if (_gameRouteScheduled) return;
    _gameRouteScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/game');
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appControllerProvider);
    final records = appState.records;
    if (widget.onReturnToGame == null) {
      ref.listen<int>(
        appControllerProvider.select((value) => value.liveDisplayRevision),
        (previous, next) {
          if (previous != null && next > previous) {
            _scheduleGameRoute();
          }
        },
      );
      // 独立排行榜使用路由返回，内嵌结算榜由实时页根据会话状态切换。
      if (appState.relayModeActive && appState.activeSessions.isNotEmpty) {
        _scheduleGameRoute();
      }
    }
    final groups = Leaderboard.groupAndRank(records);
    final visible =
        <({LeaderboardGroup group, RankedChallengeRecord ranked})>[];
    for (final group in groups) {
      for (final ranked in group.records) {
        if (visible.length == 15) break;
        visible.add((group: group, ranked: ranked));
      }
      if (visible.length == 15) break;
    }
    void returnToGame() {
      if (widget.onReturnToGame != null) {
        widget.onReturnToGame!();
        return;
      }
      if (appState.relayModeActive) context.go('/game');
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: returnToGame,
      child: ColoredBox(
        color: const Color(0xff080c0a),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: CustomPaint(painter: _LeaderboardBackdropPainter()),
            ),
            Column(
              children: <Widget>[
                _LeaderboardToolbar(
                  recordCount: records.length,
                  onExport: records.isEmpty
                      ? null
                      : () async {
                          final ok = await ChallengeCsvExporter.export(records);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? '排行榜已导出' : '已取消导出')),
                            );
                          }
                        },
                  onClear: records.isEmpty
                      ? null
                      : () => ref
                            .read(appControllerProvider.notifier)
                            .clearRecords(),
                ),
                Expanded(
                  child: records.isEmpty
                      ? const _EmptyLeaderboard()
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 7),
                          itemBuilder: (context, index) {
                            final entry = visible[index];
                            return _ArcadeLeaderboardRow(
                              key: ValueKey<String>(entry.ranked.record.id),
                              index: index,
                              group: entry.group,
                              ranked: entry.ranked,
                              onTap: returnToGame,
                            );
                          },
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardToolbar extends StatelessWidget {
  const _LeaderboardToolbar({
    required this.recordCount,
    required this.onExport,
    required this.onClear,
  });

  final int recordCount;
  final VoidCallback? onExport;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
    decoration: const BoxDecoration(
      color: Color(0xee0d120f),
      border: Border(bottom: BorderSide(color: Color(0xff33423a))),
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.emoji_events, color: Color(0xffffd84a), size: 34),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '荣耀排行榜',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'TOP 15',
                style: TextStyle(
                  color: Color(0xff49f7d2),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        Text(
          '$recordCount 局',
          style: const TextStyle(
            color: Color(0xff9aa7a0),
            fontWeight: FontWeight.w700,
          ),
        ),
        IconButton(
          tooltip: '导出 CSV',
          onPressed: onExport,
          color: Colors.white,
          icon: const Icon(Icons.download),
        ),
        IconButton(
          tooltip: '清空排行榜',
          onPressed: onClear,
          color: Colors.white,
          icon: const Icon(Icons.delete_sweep),
        ),
      ],
    ),
  );
}

class _ArcadeLeaderboardRow extends StatelessWidget {
  const _ArcadeLeaderboardRow({
    super.key,
    required this.index,
    required this.group,
    required this.ranked,
    required this.onTap,
  });

  final int index;
  final LeaderboardGroup group;
  final RankedChallengeRecord ranked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = ranked.record;
    final rankColor = switch (ranked.rank) {
      1 => const Color(0xffffd84a),
      2 => const Color(0xffc9d5d0),
      3 => const Color(0xffff9b55),
      _ => const Color(0xff49f7d2),
    };
    final maximum = item.maximumStrengthA > item.maximumStrengthB
        ? item.maximumStrengthA
        : item.maximumStrengthB;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + index * 35),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(24 * (1 - value), 0),
          child: child,
        ),
      ),
      child: Material(
        color: const Color(0xee101713),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: rankColor,
                  width: ranked.rank <= 3 ? 5 : 2,
                ),
                top: const BorderSide(color: Color(0xff29362f)),
                right: const BorderSide(color: Color(0xff29362f)),
                bottom: const BorderSide(color: Color(0xff29362f)),
              ),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 58,
                  child: Text(
                    '#${ranked.rank}',
                    style: TextStyle(
                      color: rankColor,
                      fontSize: ranked.rank <= 3 ? 28 : 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.challengerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        group.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff84928a),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                _LeaderboardMetric(
                  label: '时间',
                  value: '${(item.elapsedMs / 1000).toStringAsFixed(1)}s',
                  color: rankColor,
                ),
                const SizedBox(width: 14),
                _LeaderboardMetric(
                  label: '强度',
                  value: '$maximum',
                  color: Colors.white,
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 54,
                  child: Text(
                    item.result.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: item.result == ChallengeResult.success
                          ? const Color(0xff49f7d2)
                          : const Color(0xffffb020),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaderboardMetric extends StatelessWidget {
  const _LeaderboardMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Color(0xff748279), fontSize: 10),
        ),
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _EmptyLeaderboard extends StatelessWidget {
  const _EmptyLeaderboard();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.emoji_events_outlined, color: Color(0xffffd84a), size: 66),
        SizedBox(height: 14),
        Text(
          '还没人登上榜单',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 6),
        Text('完成一次挑战，抢下第一个席位', style: TextStyle(color: Color(0xff8f9d95))),
      ],
    ),
  );
}

class _LeaderboardBackdropPainter extends CustomPainter {
  const _LeaderboardBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff49f7d2).withValues(alpha: 0.055)
      ..strokeWidth = 1;
    const gap = 44.0;
    for (var x = 0.0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WaveformEditorDialog extends StatefulWidget {
  const _WaveformEditorDialog();

  @override
  State<_WaveformEditorDialog> createState() => _WaveformEditorDialogState();
}

class _WaveformEditorDialogState extends State<_WaveformEditorDialog> {
  final name = TextEditingController();
  final List<
    ({
      TextEditingController duration,
      TextEditingController frequency,
      TextEditingController pulse,
    })
  >
  steps = [];

  @override
  void initState() {
    super.initState();
    _addStep();
  }

  void _addStep() => setState(() {
    steps.add((
      duration: TextEditingController(text: '500'),
      frequency: TextEditingController(text: '35'),
      pulse: TextEditingController(text: '45'),
    ));
  });

  @override
  void dispose() {
    name.dispose();
    for (final step in steps) {
      step.duration.dispose();
      step.frequency.dispose();
      step.pulse.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建波形'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '波形名称'),
            ),
            const SizedBox(height: 12),
            ...List<Widget>.generate(steps.length, (index) {
              final step = steps[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: step.duration,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '持续 ms'),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: step.frequency,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '频率 Hz'),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: step.pulse,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '脉冲 us'),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除步骤',
                      onPressed: steps.length == 1
                          ? null
                          : () => setState(() => steps.removeAt(index)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addStep,
                icon: const Icon(Icons.add),
                label: const Text('添加步骤'),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          EmsWaveform(
            id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
            name: name.text.trim(),
            custom: true,
            steps: steps
                .map(
                  (step) => WaveformStep(
                    durationMs: int.tryParse(step.duration.text) ?? 0,
                    frequency: int.tryParse(step.frequency.text) ?? -1,
                    pulseWidth: int.tryParse(step.pulse.text) ?? -1,
                  ),
                )
                .toList(growable: false),
          ),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

class _WaveformPreviewPainter extends CustomPainter {
  const _WaveformPreviewPainter(
    this.waveform, {
    required this.frequencyColor,
    required this.pulseColor,
    required this.gridColor,
  });
  final EmsWaveform? waveform;
  final Color frequencyColor;
  final Color pulseColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final waveform = this.waveform;
    if (waveform == null || waveform.steps.isEmpty) return;
    final grid = Paint()..color = gridColor;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      grid,
    );
    final frequency = Path();
    final pulse = Path();
    var elapsed = 0;
    for (var index = 0; index < waveform.steps.length; index++) {
      final step = waveform.steps[index];
      final x = waveform.durationMs == 0
          ? 0.0
          : elapsed / waveform.durationMs * size.width;
      final fy = size.height - step.frequency.clamp(0, 100) / 100 * size.height;
      final py =
          size.height - step.pulseWidth.clamp(0, 100) / 100 * size.height;
      if (index == 0) {
        frequency.moveTo(x, fy);
        pulse.moveTo(x, py);
      } else {
        frequency.lineTo(x, fy);
        pulse.lineTo(x, py);
      }
      elapsed += step.durationMs;
    }
    canvas.drawPath(
      frequency,
      Paint()
        ..color = frequencyColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      pulse,
      Paint()
        ..color = pulseColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPreviewPainter oldDelegate) =>
      oldDelegate.waveform != waveform ||
      oldDelegate.frequencyColor != frequencyColor ||
      oldDelegate.pulseColor != pulseColor ||
      oldDelegate.gridColor != gridColor;
}

class _PlayerDraft {
  _PlayerDraft({required String waveformId})
    : values = _ChannelDraft(waveformId: waveformId);

  String duration = '60';
  final _ChannelDraft values;

  void applyPreset(GamePreset preset, List<EmsWaveform> waveforms) {
    // 预设波形不存在时保留当前波形，避免自定义波形被删除后配置失效。
    duration = '${preset.durationSeconds}';
    values
      ..start = '${preset.startStrength}'
      ..maximum = '${preset.maxStrength}'
      ..every = '${preset.increaseEverySeconds}'
      ..increaseBy = '${preset.increaseBy}';
    if (waveforms.any((item) => item.id == preset.waveformId)) {
      values.waveformId = preset.waveformId;
    }
  }

  void applyConfig(EmsGameConfig config) {
    final channel = config.channels == ChannelSelection.b
        ? config.channelB
        : config.channelA;
    duration = '${config.durationSeconds}';
    values
      ..start = '${channel.startStrength}'
      ..maximum = '${channel.maxStrength}'
      ..every = '${channel.increaseEverySeconds}'
      ..increaseBy = '${channel.increaseBy}'
      ..waveformId = channel.waveformId;
  }

  GamePreset toPreset({
    required String id,
    required String name,
    required GamePresetCategory category,
  }) {
    final durationSeconds = _parsePositive(duration, '挑战时长');
    if (durationSeconds < 5 || durationSeconds > 7200) {
      throw ArgumentError('挑战时长需要 5 秒到 120 分钟');
    }
    final channelConfig = values.toConfig()..validate();
    return GamePreset(
      id: id,
      name: name,
      durationSeconds: durationSeconds,
      startStrength: channelConfig.startStrength,
      maxStrength: channelConfig.maxStrength,
      increaseEverySeconds: channelConfig.increaseEverySeconds,
      increaseBy: channelConfig.increaseBy,
      waveformId: channelConfig.waveformId,
      category: category,
      custom: true,
    );
  }

  List<EmsGameConfig> toRelayConfigs(ConnectedDeviceState device) {
    final channelConfig = values.toConfig();
    final durationSeconds = _parsePositive(duration, '挑战时长');
    return <EmsGameConfig>[
      EmsGameConfig(
        challengerName: 'A 通道等待位',
        deviceId: device.id,
        protocol: device.protocol,
        channels: ChannelSelection.a,
        durationSeconds: durationSeconds,
        channelA: channelConfig,
        channelB: channelConfig,
        channelsLinked: false,
      ),
      EmsGameConfig(
        challengerName: 'B 通道等待位',
        deviceId: device.id,
        protocol: device.protocol,
        channels: ChannelSelection.b,
        durationSeconds: durationSeconds,
        channelA: channelConfig,
        channelB: channelConfig,
        channelsLinked: false,
      ),
    ];
  }
}

GamePresetCategory _categoryForRole(DeviceGameRole role) =>
    role == DeviceGameRole.couple
    ? GamePresetCategory.heart
    : GamePresetCategory.endurance;

String? _matchingPresetId(EmsGameConfig config, List<GamePreset> presets) {
  final channel = config.channels == ChannelSelection.b
      ? config.channelB
      : config.channelA;
  return presets
      .firstWhereOrNull(
        (preset) =>
            preset.durationSeconds == config.durationSeconds &&
            preset.startStrength == channel.startStrength &&
            preset.maxStrength == channel.maxStrength &&
            preset.increaseEverySeconds == channel.increaseEverySeconds &&
            preset.increaseBy == channel.increaseBy &&
            preset.waveformId == channel.waveformId,
      )
      ?.id;
}

class _ChannelDraft {
  _ChannelDraft({required this.waveformId});
  String start = '10';
  String maximum = '60';
  String every = '10';
  String increaseBy = '5';
  String waveformId;

  ChannelGameConfig toConfig() => ChannelGameConfig(
    startStrength: _parseNonNegative(start, '起始强度'),
    maxStrength: _parseNonNegative(maximum, '最高强度'),
    increaseEverySeconds: _parsePositive(every, '增长间隔'),
    increaseBy: _parsePositive(increaseBy, '增长值'),
    waveformId: waveformId,
  );
}

int _parsePositive(String value, String label) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed <= 0) throw ArgumentError('$label 必须是大于 0 的整数');
  return parsed;
}

int _parseNonNegative(String value, String label) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed < 0) throw ArgumentError('$label 必须是非负整数');
  return parsed;
}

String _batteryText(DeviceTelemetry telemetry) {
  if (telemetry.batteryPercent == null) return '读取中';
  final suffix = telemetry.batteryStale ? '（过期）' : '';
  return '${telemetry.batteryPercent}%$suffix';
}

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 10, 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...actions,
          ],
        ),
      ),
      Expanded(child: child),
    ],
  );
}

class Metric extends StatelessWidget {
  const Metric({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 140,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class MessagePanel extends StatelessWidget {
  const MessagePanel({super.key, required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.zero,
      child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
