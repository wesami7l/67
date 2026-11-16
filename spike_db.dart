import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'spike_db.g.dart';

/// جدول تجريبي صغير لاختبار drift على Windows.
class SpikeEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get note => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [SpikeEntries])
class SpikeDb extends _$SpikeDb {
  SpikeDb() : super(driftDatabase(name: 'wirdan_spike'));

  @override
  int get schemaVersion => 1;
}
