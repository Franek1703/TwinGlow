/// Serialize fresh source reads and publication across repository instances in
/// this app. Server rules additionally fence older revisions across clients.
class SharedCatalogQueue {
  final Map<String, Future<void>> _pending = {};

  Future<void> run(String key, Future<void> Function() operation) async {
    final previous = _pending[key] ?? Future<void>.value();
    final next = previous.then((_) => operation());
    final settled = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending[key] = settled;
    try {
      await next;
    } finally {
      if (identical(_pending[key], settled)) _pending.remove(key);
    }
  }
}
