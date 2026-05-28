# Cross-context references use correlation IDs, not foreign keys

Domain contexts reference identities owned by other contexts by storing a plain correlation id rather than a database foreign key — e.g. Family's `ParentProfile.identity_id` points at an Accounts `User` with no FK constraint.

We accept losing database-level referential integrity across context boundaries in exchange for keeping each bounded context independently migratable, testable, and reasoned-about: a context's schema can change without a hard DB coupling to another context's tables. Integrity across the boundary is upheld by the application and events, not the database.

## Consequences

- A dangling correlation id is possible at the DB level; cleanup/consistency is an application concern (e.g. GDPR deletion flows must fan out across contexts).
- Cross-context reads go through ACLs/projections, never SQL joins across context tables.
