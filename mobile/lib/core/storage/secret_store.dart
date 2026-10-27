class MemorySecretStore {
  MemorySecretStore([Map<String, String>? seed]) : data = seed ?? <String, String>{};

  final Map<String, String> data;

  Future<void> write(String key, String value) async => data[key] = value;

  Future<String?> read(String key) async => data[key];

  Future<void> delete(String key) async => data.remove(key);
}
