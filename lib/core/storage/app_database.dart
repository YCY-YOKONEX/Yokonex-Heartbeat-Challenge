import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yokonex_ems_game/core/model/models.dart';

class AppDatabase {
  Database? _database;

  Future<void> initialize() async {
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final root = await getDatabasesPath();
    final path = '$root${Platform.pathSeparator}ems_challenge.db';
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE protocol_mappings(
            device_id TEXT PRIMARY KEY,
            protocol TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE waveforms(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            data TEXT NOT NULL,
            custom INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE challenge_records(
            id TEXT PRIMARY KEY,
            challenger_name TEXT NOT NULL,
            config_fingerprint TEXT NOT NULL,
            config_json TEXT NOT NULL,
            protocol TEXT NOT NULL,
            channels TEXT NOT NULL,
            result TEXT NOT NULL,
            elapsed_ms INTEGER NOT NULL,
            max_strength_a INTEGER NOT NULL,
            max_strength_b INTEGER NOT NULL,
            final_strength_a INTEGER NOT NULL,
            final_strength_b INTEGER NOT NULL,
            battery_start INTEGER,
            battery_end INTEGER,
            started_at TEXT NOT NULL,
            finished_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_challenge_rank ON challenge_records(config_fingerprint, result, elapsed_ms DESC)',
        );
      },
    );
  }

  Database get _db => _database ?? (throw StateError('数据库尚未初始化'));

  Future<DeviceProtocol?> protocolFor(String deviceId) async {
    final rows = await _db.query(
      'protocol_mappings',
      where: 'device_id = ?',
      whereArgs: <Object?>[deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DeviceProtocolX.fromWireName(rows.first['protocol'] as String);
  }

  Future<void> saveProtocol(String deviceId, DeviceProtocol protocol) async {
    await _db.insert('protocol_mappings', <String, Object?>{
      'device_id': deviceId,
      'protocol': protocol.wireName,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<EmsWaveform>> loadWaveforms() async {
    final rows = await _db.query('waveforms', orderBy: 'custom ASC, name ASC');
    return rows
        .map((row) {
          final value = (jsonDecode(row['data'] as String) as Map)
              .cast<String, Object?>();
          return EmsWaveform.fromJson(value);
        })
        .toList(growable: false);
  }

  Future<void> replaceBuiltInWaveforms(List<EmsWaveform> waveforms) async {
    await _db.transaction((transaction) async {
      await transaction.delete('waveforms', where: 'custom = 0');
      for (final waveform in waveforms) {
        await transaction.insert('waveforms', <String, Object?>{
          'id': waveform.id,
          'name': waveform.name,
          'data': jsonEncode(waveform.toJson()),
          'custom': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> saveWaveform(EmsWaveform waveform) async {
    await _db.insert('waveforms', <String, Object?>{
      'id': waveform.id,
      'name': waveform.name,
      'data': jsonEncode(waveform.toJson()),
      'custom': waveform.custom ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveChallenge(ChallengeRecord record) async {
    await _db.insert(
      'challenge_records',
      record.toDatabase(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChallengeRecord>> loadChallenges() async {
    final rows = await _db.query(
      'challenge_records',
      orderBy:
          "CASE result WHEN 'success' THEN 0 ELSE 1 END, elapsed_ms DESC, finished_at DESC",
    );
    return rows.map(ChallengeRecord.fromDatabase).toList(growable: false);
  }

  Future<void> clearChallenges() => _db.delete('challenge_records');

  Future<void> close() async => _database?.close();
}
