NIP-XX
======

NostrDB - Document Database Protocol
-------------------------------------

`draft` `optional`

This NIP defines a protocol for implementing a document database on top of Nostr, to store, query, and sync structured data across relays.

## Event Structure

### Event Kind

This NIP uses kind `33102` for all database documents.

### Tag Structure

Each document event MUST include the following tags:

#### Public document

```json
{
  "kind": 33102,
  "tags": [
    ["d", "<collection>/<documentId>"],
    ["collection", "<collection>"],
  ],
  "content": "<json>",
}
```

#### Private document

```json
{
  "kind": 33102,
  "tags": [
    ["d", "<collection>/<documentId>"],
    ["collection", "<collection>"],
    ["nip44"]
  ],
  "content": "nip_44(<json>)",
}
```

#### Required Tags

- `d`: Composite identifier in format `collection/documentId` for replaceability
- `collection`: Collection name (alphanumeric, underscore, dash only)

## Operations

### Collection Reference

Collections are logical groupings of documents. A collection path is a string identifier that can be hierarchical:

- Root collection: `users`
- Subcollection: `users/user123/posts`

## Privacy Considerations

- Documents are public by default on Nostr
- Implementations SHOULD support NIP-44 encryption for sensitive data
- Use NIP-42 relay authentication for access control
- Consider separate relays for private collections
