import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

Future<AppDatabase> createAppDatabase() async {
  final documentsDirectory = await getApplicationDocumentsDirectory();
  final databaseFile = File(p.join(documentsDirectory.path, 'veil_cache_v2.sqlite'));
  return AppDatabase(NativeDatabase.createInBackground(databaseFile));
}
