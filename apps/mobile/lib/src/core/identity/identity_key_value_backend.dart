/// The storage the identity pin table lives in. Production adapts secure
/// storage to it; [InMemoryIdentityKeyValueBackend] serves tests.
abstract class IdentityKeyValueBackend {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class InMemoryIdentityKeyValueBackend implements IdentityKeyValueBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
