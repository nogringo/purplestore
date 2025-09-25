import 'dart:async';
import 'dart:convert';
import 'package:ndk/ndk.dart' as ndk;
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';
import 'document.dart';
import 'purplestore.dart';
import 'models/document_snapshot.dart';
import 'models/query_snapshot.dart';

class CollectionReference {
  final String path;
  final PurpleStore store;
  final _uuid = const Uuid();

  CollectionReference({required this.path, required this.store});

  /// Returns a reference to a document with a specific ID
  DocumentReference doc(String id) {
    return DocumentReference(id: id, collection: this);
  }

  /// Creates a new document with an auto-generated ID
  Future<DocumentReference> add(
    Map<String, dynamic> data, {
    bool private = true,
  }) async {
    final docId = _uuid.v4();
    final docRef = doc(docId);
    await docRef.set(data, private: private);
    return docRef;
  }

  /// Gets all documents in the collection
  Future<QuerySnapshot> get({int? limit}) async {
    final docs = <DocumentSnapshot>[];

    // Get documents from the global store filtered by collection
    final globalStore = stringMapStoreFactory.store('documents');
    final records = await globalStore.find(
      store.db,
      finder: Finder(filter: Filter.equals('collection', path)),
    );

    for (final record in records) {
      final docData = record.value['content'] as Map<String, dynamic>;
      final eventData = record.value['event'] as Map<String, dynamic>;
      final docId = record.value['docId'] as String;

      final createdAt = eventData['created_at'] as int;
      final tags = eventData['tags'] as List;
      final isEncrypted = tags.any(
        (tag) => tag is List && tag.isNotEmpty && tag[0] == 'nip44',
      );

      docs.add(
        DocumentSnapshot(
          id: docId,
          data: docData,
          createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
          collection: path,
          exists: true,
          isEncrypted: isEncrypted,
        ),
      );
    }

    // Also fetch from Nostr relays
    final response = store.ndk.requests.query(
      filters: [
        ndk.Filter(
          kinds: [PurpleStore.documentKind],
          tags: {
            'collection': [path],
          },
          limit: limit ?? 100,
        ),
      ],
    );

    final nostrDocs = <String, DocumentSnapshot>{};
    await for (final event in response.stream) {
      // Skip deleted documents
      if (event.tags.any((tag) => tag[0] == 'deleted' && tag[1] == 'true')) {
        continue;
      }

      // Extract document ID from d tag
      final dTag = event.tags.firstWhere(
        (tag) => tag[0] == 'd',
        orElse: () => ['d', ''],
      );
      if (dTag[1].isEmpty) continue;

      final docId = dTag[1].split('/').last;

      // Check if document is encrypted
      final isEncrypted = event.tags.any((tag) => tag[0] == 'nip44');

      // Decrypt if necessary
      String content;
      if (isEncrypted) {
        content = await decryptContent(event.content);
      } else {
        content = event.content;
      }

      // Parse document data
      final data = jsonDecode(content) as Map<String, dynamic>;

      // Store the event locally
      await storeEventLocal(docId: docId, event: event, documentData: data);

      // Add to results if not already in local results
      if (!docs.any((doc) => doc.id == docId)) {
        nostrDocs[docId] = DocumentSnapshot(
          id: docId,
          data: data,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            event.createdAt * 1000,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            event.createdAt * 1000,
          ),
          collection: path,
          exists: true,
          isEncrypted: event.tags.any((tag) => tag[0] == 'nip44'),
        );
      }
    }

    // Add Nostr documents that weren't in local store
    docs.addAll(nostrDocs.values);

    return QuerySnapshot(docs: docs, collection: path);
  }

  /// Creates a Nostr event for a document
  Future<ndk.Nip01Event> createDocumentEvent({
    required String docId,
    required Map<String, dynamic> data,
    bool private = false,
  }) async {
    final pubKey = store.ndk.accounts.getPublicKey();
    if (pubKey == null) {
      throw Exception(
        'No active account. Please login with a private key first.',
      );
    }

    final dTag = '$path/$docId';

    final tags = [
      ['d', dTag],
      ['collection', path],
    ];

    // Add encryption tag if private
    if (private) {
      tags.add(['nip44']);
    }

    final content = private
        ? await _encryptContent(jsonEncode(data))
        : jsonEncode(data);

    return ndk.Nip01Event(
      pubKey: pubKey,
      kind: PurpleStore.documentKind,
      tags: tags,
      content: content,
    );
  }

  Future<String> _encryptContent(String content) async {
    final account = store.ndk.accounts.getLoggedAccount();
    if (account == null) {
      throw Exception('No logged in account for encryption');
    }

    final pubKey = account.pubkey;

    final encrypted = await account.signer.encryptNip44(
      plaintext: content,
      recipientPubKey: pubKey,
    );

    if (encrypted == null) {
      throw Exception('Failed to encrypt content');
    }

    return encrypted;
  }

  Future<String> decryptContent(String encryptedContent) async {
    final account = store.ndk.accounts.getLoggedAccount();
    if (account == null) {
      throw Exception('No logged in account for decryption');
    }

    final pubKey = account.pubkey;

    try {
      final decrypted = await account.signer.decryptNip44(
        ciphertext: encryptedContent,
        senderPubKey: pubKey,
      );

      if (decrypted == null) {
        throw Exception('Failed to decrypt content');
      }

      return decrypted;
    } catch (e) {
      throw Exception('Failed to decrypt content: $e');
    }
  }

  /// Stores a Nostr event locally in Sembast
  Future<void> storeEventLocal({
    required String docId,
    required ndk.Nip01Event event,
    required Map<String, dynamic> documentData,
  }) async {
    // Use a single global store for all documents
    final globalStore = stringMapStoreFactory.store('documents');
    final key = '$path/$docId';

    // Store with minimal structure
    await globalStore.record(key).put(store.db, {
      'event': event.toJson(),
      'collection': path,
      'docId': docId,
      'content': documentData, // Always decrypted/parsed JSON
    });
  }

  /// Listen to real-time updates for this collection
  Stream<QuerySnapshot> onSnapshot() {
    final controller = StreamController<QuerySnapshot>.broadcast();

    // Get initial data
    get().then((snapshot) {
      controller.add(snapshot);
    });

    // Generate a unique subscription ID
    final subId = 'col_${path}_${DateTime.now().millisecondsSinceEpoch}';

    // Subscribe to Nostr events for this collection
    final subscription = store.ndk.requests.subscription(
      filters: [
        ndk.Filter(
          kinds: [PurpleStore.documentKind],
          tags: {
            'collection': [path],
          },
        ),
      ],
      id: subId,
    );

    subscription.stream.listen((event) async {
      // Check if it's a deletion
      final isDeleted = event.tags.any(
        (tag) => tag.isNotEmpty && tag[0] == 'deleted' && tag[1] == 'true',
      );

      // Extract document ID
      final dTag = event.tags.firstWhere(
        (tag) => tag[0] == 'd',
        orElse: () => ['d', ''],
      );
      if (dTag[1].isEmpty) return;

      final docId = dTag[1].split('/').last;

      if (isDeleted) {
        // Remove from local store
        final globalStore = stringMapStoreFactory.store('documents');
        final key = '$path/$docId';
        await globalStore.record(key).delete(store.db);
      } else {
        // Check if document is encrypted
        final isEncrypted = event.tags.any((tag) => tag[0] == 'nip44');

        // Decrypt if necessary
        String content;
        if (isEncrypted) {
          content = await decryptContent(event.content);
        } else {
          content = event.content;
        }

        // Parse and store
        final data = jsonDecode(content) as Map<String, dynamic>;
        await storeEventLocal(docId: docId, event: event, documentData: data);
      }

      // Emit updated snapshot
      final updatedSnapshot = await get();
      controller.add(updatedSnapshot);
    });

    // Clean up on cancel
    controller.onCancel = () {
      store.ndk.requests.closeSubscription(subId);
    };

    return controller.stream;
  }
}
