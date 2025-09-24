import 'document_snapshot.dart';

class QuerySnapshot {
  final List<DocumentSnapshot> docs;
  final String collection;

  const QuerySnapshot({
    required this.docs,
    required this.collection,
  });

  int get size => docs.length;

  bool get isEmpty => docs.isEmpty;

  bool get isNotEmpty => docs.isNotEmpty;
}