import 'dart:typed_data';

enum BleAvailability {
  unknown,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn,
}

enum BleConnectionPhase { connecting, connected, disconnected, failed }

class BleScanResult {
  const BleScanResult({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.advertisedServiceUuids,
  });

  final String deviceId;
  final String name;
  final int rssi;
  final Set<String> advertisedServiceUuids;
}

class BleConnectionEvent {
  const BleConnectionEvent({
    required this.deviceId,
    required this.phase,
    this.message = '',
  });
  final String deviceId;
  final BleConnectionPhase phase;
  final String message;
}

class BleNotification {
  const BleNotification({required this.deviceId, required this.value});
  final String deviceId;
  final Uint8List value;
}

class BleCharacteristic {
  const BleCharacteristic({
    required this.uuid,
    required this.writeWithResponse,
    required this.writeWithoutResponse,
    required this.notify,
    required this.indicate,
  });

  final String uuid;
  final bool writeWithResponse;
  final bool writeWithoutResponse;
  final bool notify;
  final bool indicate;
}

class BleService {
  const BleService({required this.uuid, required this.characteristics});
  final String uuid;
  final List<BleCharacteristic> characteristics;
}

abstract interface class BleAdapter {
  Stream<BleAvailability> get availabilityChanges;
  Stream<BleScanResult> get scanResults;
  Stream<BleConnectionEvent> get connectionEvents;
  Stream<BleNotification> get notifications;

  Future<BleAvailability> getAvailability();
  Future<void> requestPermissions();
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect(String deviceId);
  Future<List<BleService>> discoverServices(String deviceId);
  Future<void> subscribe(String deviceId);
  Future<void> write(
    String deviceId,
    Uint8List value, {
    required bool withResponse,
  });
  Future<void> dispose();
}
