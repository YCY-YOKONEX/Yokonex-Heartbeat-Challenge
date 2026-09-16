import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart' as universal;
import 'package:yokonex_ems_game/core/platform/ble_adapter.dart';

class UniversalBleAdapter implements BleAdapter {
  UniversalBleAdapter() {
    _subscriptions.add(
      universal.UniversalBle.scanStream.listen((device) {
        _scanController.add(
          BleScanResult(
            deviceId: device.deviceId,
            name: device.name ?? '',
            rssi: device.rssi ?? -127,
            advertisedServiceUuids: device.services
                .map((uuid) => uuid.toLowerCase())
                .toSet(),
          ),
        );
      }),
    );
    _subscriptions.add(
      universal.UniversalBle.availabilityStream.listen(
        (value) => _availabilityController.add(_availability(value)),
      ),
    );
  }

  static const String serviceUuid = '0000ff30-0000-1000-8000-00805f9b34fb';
  static const String writeUuid = '0000ff31-0000-1000-8000-00805f9b34fb';
  static const String notifyUuid = '0000ff32-0000-1000-8000-00805f9b34fb';

  final _availabilityController = StreamController<BleAvailability>.broadcast();
  final _scanController = StreamController<BleScanResult>.broadcast();
  final _connectionController =
      StreamController<BleConnectionEvent>.broadcast();
  final _notificationController = StreamController<BleNotification>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  final Map<String, StreamSubscription<Uint8List>> _notificationSubscriptions =
      <String, StreamSubscription<Uint8List>>{};
  final Map<String, BleCharacteristic> _characteristics =
      <String, BleCharacteristic>{};
  final Set<String> _observed = <String>{};

  @override
  Stream<BleAvailability> get availabilityChanges =>
      _availabilityController.stream;
  @override
  Stream<BleScanResult> get scanResults => _scanController.stream;
  @override
  Stream<BleConnectionEvent> get connectionEvents =>
      _connectionController.stream;
  @override
  Stream<BleNotification> get notifications => _notificationController.stream;

  @override
  Future<BleAvailability> getAvailability() async => _availability(
    await universal.UniversalBle.getBluetoothAvailabilityState(),
  );

  @override
  Future<void> requestPermissions() =>
      universal.UniversalBle.requestPermissions(withAndroidFineLocation: false);

  @override
  Future<void> startScan() => universal.UniversalBle.startScan(
    scanFilter: universal.ScanFilter(
      withServices: const <String>[serviceUuid],
      withNamePrefix: const <String>['YYC-DJ'],
    ),
    platformConfig: universal.PlatformConfig(
      android: universal.AndroidOptions(
        requestLocationPermission: false,
        scanMode: universal.AndroidScanMode.lowLatency,
        legacy: true,
      ),
    ),
  );

  @override
  Future<void> stopScan() => universal.UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId) async {
    if (_observed.add(deviceId)) {
      _subscriptions.add(
        universal.UniversalBle.connectionStream(deviceId).listen((connected) {
          _connectionController.add(
            BleConnectionEvent(
              deviceId: deviceId,
              phase: connected
                  ? BleConnectionPhase.connected
                  : BleConnectionPhase.disconnected,
            ),
          );
        }),
      );
    }
    _connectionController.add(
      BleConnectionEvent(
        deviceId: deviceId,
        phase: BleConnectionPhase.connecting,
      ),
    );
    try {
      await universal.UniversalBle.connect(deviceId);
    } catch (error) {
      _connectionController.add(
        BleConnectionEvent(
          deviceId: deviceId,
          phase: BleConnectionPhase.failed,
          message: error.toString(),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect(String deviceId) =>
      universal.UniversalBle.disconnect(deviceId);

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    final services = await universal.UniversalBle.discoverServices(deviceId);
    return services
        .map((service) {
          final mapped = service.characteristics
              .map((characteristic) {
                final value = BleCharacteristic(
                  uuid: characteristic.uuid.toLowerCase(),
                  writeWithResponse: characteristic.properties.contains(
                    universal.CharacteristicProperty.write,
                  ),
                  writeWithoutResponse: characteristic.properties.contains(
                    universal.CharacteristicProperty.writeWithoutResponse,
                  ),
                  notify: characteristic.properties.contains(
                    universal.CharacteristicProperty.notify,
                  ),
                  indicate: characteristic.properties.contains(
                    universal.CharacteristicProperty.indicate,
                  ),
                );
                _characteristics[_key(
                      deviceId,
                      service.uuid,
                      characteristic.uuid,
                    )] =
                    value;
                return value;
              })
              .toList(growable: false);
          return BleService(
            uuid: service.uuid.toLowerCase(),
            characteristics: mapped,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> subscribe(String deviceId) async {
    final key = _key(deviceId, serviceUuid, notifyUuid);
    final characteristic = _characteristics[key];
    if (characteristic == null) throw StateError('订阅前必须先发现蓝牙服务');
    await _notificationSubscriptions.remove(deviceId)?.cancel();
    _notificationSubscriptions[deviceId] =
        universal.UniversalBle.characteristicValueStream(
          deviceId,
          notifyUuid,
        ).listen(
          (value) => _notificationController.add(
            BleNotification(deviceId: deviceId, value: value),
          ),
        );
    if (characteristic.notify) {
      await universal.UniversalBle.subscribeNotifications(
        deviceId,
        serviceUuid,
        notifyUuid,
      );
    } else if (characteristic.indicate) {
      await universal.UniversalBle.subscribeIndications(
        deviceId,
        serviceUuid,
        notifyUuid,
      );
    } else {
      throw StateError('设备通知特征不可订阅');
    }
  }

  @override
  Future<void> write(
    String deviceId,
    Uint8List value, {
    required bool withResponse,
  }) {
    return universal.UniversalBle.write(
      deviceId,
      serviceUuid,
      writeUuid,
      value,
      withoutResponse: !withResponse,
    );
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _notificationSubscriptions.values) {
      await subscription.cancel();
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _availabilityController.close();
    await _scanController.close();
    await _connectionController.close();
    await _notificationController.close();
  }

  static String _key(String deviceId, String service, String characteristic) =>
      '$deviceId|${service.toLowerCase()}|${characteristic.toLowerCase()}';

  static BleAvailability _availability(universal.AvailabilityState value) =>
      switch (value) {
        universal.AvailabilityState.poweredOn => BleAvailability.poweredOn,
        universal.AvailabilityState.poweredOff => BleAvailability.poweredOff,
        universal.AvailabilityState.unauthorized =>
          BleAvailability.unauthorized,
        universal.AvailabilityState.unsupported => BleAvailability.unsupported,
        _ => BleAvailability.unknown,
      };
}
