import 'package:meta/meta.dart';

@immutable
class DocumentSnapshot {
  final String id;
  final Map<String, dynamic>? _data;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String collection;
  final bool exists;
  final bool isEncrypted;

  const DocumentSnapshot({
    required this.id,
    required Map<String, dynamic>? data,
    required this.createdAt,
    required this.updatedAt,
    required this.collection,
    required this.exists,
    this.isEncrypted = false,
  }) : _data = data;

  Map<String, dynamic>? data() => _data;

  T? get<T>(String field) {
    if (_data == null) return null;
    return _data[field] as T?;
  }

  @override
  String toString() =>
      'DocumentSnapshot(id: $id, collection: $collection, exists: $exists)';
}
