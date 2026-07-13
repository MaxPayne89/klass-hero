# Business registration is structured Provider data with a curated country, captured atomically

The business vetting track (ADR-0008) includes a `:business_registration` step (B2, issue #956):
a `:business` **Provider** proves it is a legally registered entity. The step could be satisfied by
a bare document upload — the same shape as every other document step — but #956 asks for more: the
admin review queue must surface the **legal business name** and **registration number** *without
opening the file*, and the registration number must be stored as **structured data** to enable
future automated lookups against company registries. That pushes three questions a future reader
will otherwise puzzle over: where do these facts live, how is the country of registration modelled,
and what is the transactional relationship between the fields and the uploaded document.

## Decision

- **Registration facts are three values on the Provider, not on the document and not an entity.**
  `legal_business_name`, `registration_number`, and `registration_country` are columns on the
  `providers` table (mirroring the Responsible Person fields of ADR-0010). They are *facts about the
  entity*, queryable by the admin read model with a single join — no `VerificationDocument` metadata
  column, no `business_registrations` table. The uploaded `VerificationDocument` remains the evidence;
  the provider row holds the structured claim.

- **`registration_country` is a curated string, not an `Ecto.Enum` or a full ISO list.** Stored as
  `"DE" | "GB" | "OTHER"`, validated by `validate_inclusion`. #956 names exactly three guidance
  buckets (Germany → Gewerbeanmeldung/Handelsregisterauszug; UK → Companies House; Other EU →
  equivalent national document), so three values suffice. A plain string (over an enum) lets the
  whitelist widen — adding France, Austria, etc. — without a schema migration, and keeps the value
  lookup-friendly. `"OTHER"` is an honest sentinel: it records that the platform cannot yet do a
  precise registry lookup, rather than pretending to a precision the data does not have.

- **A dedicated narrow changeset is the sole mutator.** `business_registration_changeset/2` casts
  only these three fields and is excluded from every profile-edit and completion whitelist, exactly
  as `responsible_person_changeset/2` is — so `submit_business_registration/2` is their only write
  path.

- **Submission is atomic, but never resets vetting.** `submit_business_registration/2` uploads the
  file to storage *first* (storage is not transactional), then writes the three provider columns and
  inserts the `VerificationDocument` in one `Repo.transaction`; the field changeset is validated
  before the upload so invalid input never orphans a file. Unlike the Responsible Person (ADR-0010),
  registration carries **no `requires` edge** and its change **does not** reset any step or unverify
  the business — it is a fact about the entity, independent of who is accountable. The step advances
  only when an admin later approves the document, on the existing generic
  `AdvanceVettingStepOnDocumentReview` path.

## Consequences

- The admin queue joins two extra provider columns (still one join, no N+1) and gates their display
  on `document_type == :business_registration`.
- Adding a supported country is a one-line change to the curated list plus a guidance string and a
  German translation — no migration.
- Because B2 never resets, a business can correct and resubmit its registration document after a
  rejection without disturbing the rest of the checklist; a resubmission simply produces a new
  pending document that the read-time merge surfaces as "Under review".
- If a future integration needs a normalized country for automated registry calls, `"OTHER"` rows
  will need enrichment — the honest sentinel makes that gap explicit rather than hidden behind a
  free-text field.

## Alternatives considered

- **`Ecto.Enum` for the country.** Rejected: every new country would force a migration, and baking
  `:other` into the type couples the schema to today's three-bucket UX.
- **Full ISO 3166 dropdown storing alpha-2.** Rejected for now: ~30 entries is overkill for a
  DE-first platform and still needs per-country guidance for only two of them; the curated list can
  grow into this if demand appears.
- **Metadata on the `VerificationDocument`.** Rejected: the admin queue would have to read document
  rows to surface entity facts, and the data would be tied to a specific upload rather than to the
  business.
- **Two separate commands (fields, then document).** Rejected: a failure between them would leave an
  admin looking at a document with a blank registration number, or fields with no evidence.
