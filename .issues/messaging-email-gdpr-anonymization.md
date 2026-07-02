# Messaging — anonymize inbound-email + reply PII on GDPR user delete

Type: tech-debt / GDPR

## Problem

`KlassHero.Messaging.anonymize_data_for_user/1` (use case `AnonymizeUserData`) scrubs only
`messages` and `conversation_participants`. It never touches the email tables:

- `email_replies.body` — free-text an admin typed; can contain the sender's PII. Survives untouched.
- `email_replies.sent_by_id`, `inbound_emails.read_by_id` — only protected by DB
  `on_delete: :nilify_all` FKs (migrations `20260320103208_create_inbound_emails`,
  `20260321133301_add_email_content_and_replies`). A hard user delete nilifies the FK but leaves
  the reply body.

So a GDPR erasure request for a user who authored email replies leaves their text in the DB.

## What to do

- Extend `AnonymizeUserData` (or add a dedicated pass) to blank `email_replies.body` (e.g. `"[deleted]"`)
  for replies where `sent_by_id == user_id`, mirroring the existing `messages` `[deleted]` treatment.
- Decide whether inbound-email metadata (`from_address`/`from_name`) for a deleted *sender* needs
  scrubbing — inbound senders are usually external parents, not app users, so likely out of scope,
  but confirm.
- Keep the existing `DBConnection`/`Postgrex` rescue pattern used by the messages anonymize path.

## Acceptance criteria

- [ ] `anonymize_data_for_user/1` blanks reply bodies authored by the deleted user
- [ ] Test asserting a reply body is `[deleted]` after anonymization
- [ ] Full suite green

## Blocked by

None. Surfaced during the Messaging flatten (Slice 4).
