import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../security/platform_security_service.dart';
import 'app_database.dart';
import 'secure_storage_service.dart';

Future<AppDatabase> createAppDatabase({
  required SecureStorageService secureStorage,
  required PlatformSecurityService platformSecurityService,
}) async {
  final appSupportDirectory = await getApplicationSupportDirectory();
  final databaseDirectory = Directory(
    p.join(appSupportDirectory.path, '.veil', 'cache'),
  );
  await databaseDirectory.create(recursive: true);
  await platformSecurityService.excludePathFromBackup(databaseDirectory.path);
  final databasePath = p.join(databaseDirectory.path, 'veil_cache_v3.sqlite');
  final databaseFile = File(databasePath);
  final databaseKeyHex = await secureStorage.readOrCreateDatabaseKeyHex();
  final legacyPlaintextPath = (await _legacyPlaintextDatabaseFile()).path;

  return AppDatabase(
    NativeDatabase.createInBackground(
      databaseFile,
      isolateSetup: () async {
        await _migrateLegacyPlaintextDatabase(
          legacyPlaintextPath: legacyPlaintextPath,
          encryptedDatabasePath: databasePath,
          key: databaseKeyHex,
        );
      },
      setup: (database) {
        _applyCipherKey(database, databaseKeyHex);
        database.select('SELECT count(*) FROM sqlite_master;');
        database.execute('PRAGMA journal_mode = WAL;');
        database.execute('PRAGMA secure_delete = ON;');
        database.execute('PRAGMA foreign_keys = ON;');
        database.execute('PRAGMA temp_store = MEMORY;');
        database.execute('PRAGMA trusted_schema = OFF;');
      },
    ),
  );
}

Future<File> _legacyPlaintextDatabaseFile() async {
  final documentsDirectory = await getApplicationDocumentsDirectory();
  return File(p.join(documentsDirectory.path, 'veil_cache_v2.sqlite'));
}

Future<void> _migrateLegacyPlaintextDatabase({
  required String legacyPlaintextPath,
  required String encryptedDatabasePath,
  required String key,
}) async {
  final legacyPlaintextFile = File(legacyPlaintextPath);
  final encryptedDatabaseFile = File(encryptedDatabasePath);
  if (!await legacyPlaintextFile.exists() ||
      await encryptedDatabaseFile.exists()) {
    return;
  }

  final workingCopy = File('${encryptedDatabaseFile.path}.tmp');
  if (await workingCopy.exists()) {
    await workingCopy.delete();
  }
  await legacyPlaintextFile.copy(workingCopy.path);

  final database = sqlite.sqlite3.open(workingCopy.path);
  try {
    _rekeyDatabase(database, key);
    database.execute('VACUUM;');
  } finally {
    database.close();
  }

  await workingCopy.rename(encryptedDatabaseFile.path);
  await legacyPlaintextFile.delete();
}

void _applyCipherKey(sqlite.Database database, String key) {
  database.execute("PRAGMA key = '${_escapeSqlLiteral(key)}';");
}

void _rekeyDatabase(sqlite.Database database, String key) {
  database.execute("PRAGMA rekey = '${_escapeSqlLiteral(key)}';");
}

String _escapeSqlLiteral(String value) => value.replaceAll("'", "''");
