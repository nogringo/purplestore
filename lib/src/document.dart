import 'dart:async';
import 'dart:convert';
import 'package:ndk/ndk.dart' as ndk;
import 'package:sembast/sembast.dart';
import 'collection.dart';
import 'models/document_snapshot.dart';
import 'purplestore.dart';

class DocumentReference {
  final String id;
  final CollectionReference collection;

  DocumentReference({required this.id, required this.collection});

  String get path => '${collection.path}/$id';

  /// Creates or overwrites a document
  Future<void> set(Map<String, dynamic> data, {bool private = true}) async {
    // Create Nostr event
    final event = await collection.createDocumentEvent(
      docId: id,
      data: data,
      private: private,
    );

    // Broadcast to Nostr network
    collection.store.ndk.broadcast.broadcast(nostrEvent: event);

    // Store the event locally
    await collection.storeEventLocal(
      docId: id,
      event: event,
      documentData: data,
    );
  }

  /// Updates fields in a document (merge)
  Future<void> update(Map<String, dynamic> data) async {
    // Get existing document
    final snapshot = await get();
    if (!snapshot.exists) {
      throw Exception('Document does not exist');
    }

    // Merge with existing data
    final currentData = snapshot.data() ?? {};
    final mergedData = {...currentData, ...data};

    // Set with merged data
    await set(mergedData);
  }

  /// Deletes a document
  Future<void> delete() async {
    // First, get the current document event to find its ID
    final response = collection.store.ndk.requests.query(
      filters: [
        ndk.Filter(
          kinds: [PurpleStore.documentKind],
          dTags: ['${collection.path}/$id'],
          limit: 1,
        ),
      ],
    );

    String? eventIdToDelete;
    await for (final event in response.stream) {
      eventIdToDelete = event.id;
      break;
    }

    if (eventIdToDelete != null) {
      // Broadcast NIP-09 deletion event
      collection.store.ndk.broadcast.broadcastDeletion(
        eventId: eventIdToDelete,
      );
    }

    // Remove from local store
    final globalStore = stringMapStoreFactory.store('documents');
    final key = '${collection.path}/$id';
    await globalStore.record(key).delete(collection.store.db);
  }

  /// Gets a document snapshot
  Future<DocumentSnapshot> get() async {
    // Use the global store with composite key
    final globalStore = stringMapStoreFactory.store('documents');
    final key = '${collection.path}/$id';
    final record = await globalStore.record(key).get(collection.store.db);

    if (record != null) {
      final docData = record['content'] as Map<String, dynamic>;
      final eventData = record['event'] as Map<String, dynamic>;

      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List;
      final isEncrypted = tags.any(
        (tag) => tag is List && tag.isNotEmpty && tag[0] == 'nip44',
      );

      return DocumentSnapshot(
        id: id,
        data: docData,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
        collection: collection.path,
        exists: true,
        isEncrypted: isEncrypted,
      );
    }

    // Try to fetch from Nostr if not in local store
    final response = collection.store.ndk.requests.query(
      filters: [
        ndk.Filter(
          kinds: [PurpleStore.documentKind],
          dTags: ['${collection.path}/$id'],
          limit: 1,
        ),
      ],
    );

    await for (final event in response.stream) {
      if (event.tags.any((tag) => tag[0] == 'deleted' && tag[1] == 'true')) {
        // Document was deleted
        break;
      }

      // Check if document is encrypted
      final isEncrypted = event.tags.any((tag) => tag[0] == 'nip44');

      // Decrypt if necessary
      String content;
      if (isEncrypted) {
        content = await collection.decryptContent(event.content);
      } else {
        content = event.content;
      }

      // Parse document data
      final data = jsonDecode(content) as Map<String, dynamic>;

      // Store the event locally
      await collection.storeEventLocal(
        docId: id,
        event: event,
        documentData: data,
      );

      return DocumentSnapshot(
        id: id,
        data: data,
        createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        collection: collection.path,
        exists: true,
        isEncrypted: isEncrypted,
      );
    }

    // Document doesn't exist
    return DocumentSnapshot(
      id: id,
      data: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      collection: collection.path,
      exists: false,
    );
  }

  /// Listen to real-time updates for this document
  Stream<DocumentSnapshot> onSnapshot() {
    final controller = StreamController<DocumentSnapshot>.broadcast();

    // Get initial data
    get().then((snapshot) {
      controller.add(snapshot);
    });

    // Generate a unique subscription ID
    final subId =
        'doc_${collection.path}_${id}_${DateTime.now().millisecondsSinceEpoch}';

    // Subscribe to Nostr events for this specific document
    final subscription = collection.store.ndk.requests.subscription(
      filters: [
        ndk.Filter(
          kinds: [PurpleStore.documentKind],
          dTags: ['${collection.path}/$id'],
        ),
      ],
      id: subId,
    );

    subscription.stream.listen((event) async {
      // Check if it's a deletion
      final isDeleted = event.tags.any(
        (tag) => tag.isNotEmpty && tag[0] == 'deleted' && tag[1] == 'true',
      );

      if (isDeleted) {
        // Remove from local store and emit non-existent snapshot
        final globalStore = stringMapStoreFactory.store('documents');
        final key = '${collection.path}/$id';
        await globalStore.record(key).delete(collection.store.db);

        controller.add(
          DocumentSnapshot(
            id: id,
            data: null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            collection: collection.path,
            exists: false,
          ),
        );
      } else {
        // Check if document is encrypted
        final isEncrypted = event.tags.any((tag) => tag[0] == 'nip44');

        // Decrypt if necessary
        String content;
        if (isEncrypted) {
          content = await collection.decryptContent(event.content);
        } else {
          content = event.content;
        }

        // Parse and store
        final data = jsonDecode(content) as Map<String, dynamic>;
        await collection.storeEventLocal(
          docId: id,
          event: event,
          documentData: data,
        );

        // Emit updated snapshot
        controller.add(
          DocumentSnapshot(
            id: id,
            data: data,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              event.createdAt * 1000,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              event.createdAt * 1000,
            ),
            collection: collection.path,
            exists: true,
            isEncrypted: isEncrypted,
          ),
        );
      }
    });

    // Clean up on cancel
    controller.onCancel = () {
      collection.store.ndk.requests.closeSubscription(subId);
    };

    return controller.stream;
  }

  @override
  String toString() => 'DocumentReference($path)';
}
