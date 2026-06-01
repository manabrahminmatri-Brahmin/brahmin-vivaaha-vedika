/// Small generic key/value store with a single TTL — used for hot paths
/// (e.g. profile document, payment flags) without persistence.
class TtlCache<K, V> {
  TtlCache({required this.ttl});

  final Duration ttl;
  final Map<K, _Entry<V>> _m = {};

  int get length => _m.length;

  V? get(K key) {
    final e = _m[key];
    if (e == null) return null;
    if (DateTime.now().isAfter(e.expiresAt)) {
      _m.remove(key);
      return null;
    }
    return e.value;
  }

  void set(K key, V value) {
    _m[key] = _Entry(value, DateTime.now().add(ttl));
  }

  void remove(K key) => _m.remove(key);

  void clear() => _m.clear();
}

class _Entry<V> {
  _Entry(this.value, this.expiresAt);
  final V value;
  final DateTime expiresAt;
}

