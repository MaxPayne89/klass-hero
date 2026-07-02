# Messaging — retention/cleanup job for inbound_emails + email_replies

Type: tech-debt

## Problem

`inbound_emails` and `email_replies` accumulate indefinitely. `RetentionPolicyWorker` and
`MessageCleanupWorker` operate only on conversations/messages — neither touches the email tables
(grep-confirmed). Conversations have a `retention_until` + expiry delete path; received emails and
their replies have nothing.

## What to do

- Define a retention policy for inbound emails (e.g. delete/anonymize N days after `received_at`,
  reusing the `config :klass_hero, :messaging, retention: [...]` shape).
- Add a cleanup path (new Oban worker, or extend `MessageCleanupWorker`) that prunes expired
  `inbound_emails` and cascades to `email_replies`.
- Confirm cascade behavior at the DB level (FK on `email_replies.inbound_email_id`).

## Acceptance criteria

- [ ] Documented retention window for inbound emails/replies
- [ ] Oban worker prunes expired rows; cascades to replies
- [ ] Test covering the expiry + cascade
- [ ] Full suite green

## Blocked by

None. Surfaced during the Messaging flatten (Slice 4).
