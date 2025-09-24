A database that store data on Nostr.

## Getting started

```bash
dart pub add purplestore
flutter pub add purplestore
```

```dart
final ndk = Ndk.defaultConfig();
final db = await databaseFactoryIo.openDatabase("/database.db");

final purpleStore = PurpleStore(ndk: ndk, db: db);
```

## Usage

```dart
final collectionRef = purpleStore.collection("words");

// Listen to real-time updates
final subscription = collectionRef.onSnapshot().listen((snapshot) {
    print('Collection has ${snapshot.docs.length} documents');
});

// Create or update a document
final docRef = collectionRef.doc("hello");
await docRef.set({"word": "world"});

// Add a new document with auto-generated ID
final newDoc = await collectionRef.add({"word": "galaxy"});
print('Created document with ID: ${newDoc.id}');

// Query all documents
final snapshot = await collectionRef.get();
for (var word in snapshot.docs) {
    print('Document ${word.id}: ${word.data()}');
}

// Delete a document
await docRef.delete();
```

### Query

For queries, use [Sembast](https://pub.dev/packages/sembast) directly.

```dart
import 'package:sembast/sembast.dart';

// Access the Sembast database from PurpleStore
final db = purpleStore.db;

// Query documents from the global store
final store = stringMapStoreFactory.store('documents');

// Find all documents in a collection
final finder = Finder(
  filter: Filter.equals('collection', 'users'),
);
final records = await store.find(db, finder: finder);
```

## TODO

- [ ] Query Capabilities (maybe)
- [ ] Use RxDart (maybe)

## Here is my Nostr for contact and donation.

https://nosta.me/b22b06b051fd5232966a9344a634d956c3dc33a7f5ecdcad9ed11ddc4120a7f2
