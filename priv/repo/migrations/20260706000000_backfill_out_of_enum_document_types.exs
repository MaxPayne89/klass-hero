defmodule KlassHero.Repo.Migrations.BackfillOutOfEnumDocumentTypes do
  @moduledoc """
  Normalizes `verification_documents.document_type` rows left outside the current
  enum by an earlier narrowing (#1026). Legacy values such as
  `safeguarding_certificate` and `background_check` are written nowhere in the
  current code; they are stale data that 500s every read path via `Ecto.Enum`.

  The `DocumentType` custom type now loads such rows as `:unknown` so they no
  longer crash, but this migration also normalizes the stored data to a real,
  reviewable type (`other`) so the DB matches the enum going forward. It sweeps
  any out-of-enum value, including prod rows not visible during development.

  The count logging that precedes the `UPDATE` is the HITL gate. The whole
  transform runs in one transaction, so a failure leaves data untouched.
  Idempotent: a re-run finds no out-of-enum rows.

  Irreversible: the original value is unrecoverable once backfilled, so `down/0`
  is a no-op.
  """
  use Ecto.Migration

  alias Ecto.Adapters.SQL

  require Logger

  @valid_types ~w(business_registration insurance_certificate id_document tax_certificate other)

  def up do
    repo().transaction(fn ->
      %{rows: [[stale_count]]} =
        SQL.query!(
          repo(),
          "SELECT count(*) FROM verification_documents WHERE document_type != ALL($1)",
          [@valid_types]
        )

      Logger.info(
        "[#1026] backfill_out_of_enum_document_types: normalizing #{stale_count} " <>
          "out-of-enum verification_documents rows to 'other'"
      )

      SQL.query!(
        repo(),
        "UPDATE verification_documents SET document_type = 'other' WHERE document_type != ALL($1)",
        [@valid_types]
      )
    end)
  end

  def down do
    :ok
  end
end
