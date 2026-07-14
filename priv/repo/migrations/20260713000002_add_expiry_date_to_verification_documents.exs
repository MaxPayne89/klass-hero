defmodule KlassHero.Repo.Migrations.AddExpiryDateToVerificationDocuments do
  use Ecto.Migration

  # Insurance certificates (vetting step B3, issue #957) carry a policy expiry date, so the
  # platform can warn when a certificate is expired or expiring soon. Modelled as a generic
  # nullable :date on the document row rather than an insurance-only entity: other expiring
  # document types (individual-track safeguarding certificate, #558) share the same column,
  # and a future scheduled re-flag job scans a single field across types. Nullable — only
  # documents that expire populate it; the "required for insurance" rule lives in the submit
  # command, not the DB, so the shared create_changeset stays type-agnostic.
  def change do
    alter table(:verification_documents) do
      add :expiry_date, :date
    end
  end
end
