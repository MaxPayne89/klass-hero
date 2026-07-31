defmodule KlassHero.Enrollment.Domain.Services.InviteFieldValidations do
  @moduledoc """
  Shared field-shape validations for enrollment invites — the rules that
  must hold whether the row came from the CSV importer or the manual
  single-invite form. Kept in one place so bumping a length limit or the
  email regex can't silently diverge between entry points.

  Operates on any `Ecto.Changeset` whose fields include the invite field
  set; does not cast — callers decide what to cast first.

  Presence/required-field checks belong to the **caller** (cast pipeline
  + `validate_required/2`). This module assumes any value it sees is
  non-nil and validates field shape only.

  The optional second arg `today` is injected so tests can pin the clock
  for `child_date_of_birth` boundary checks; production callers omit it
  and get `Date.utc_today/0`.
  """

  import Ecto.Changeset

  @email_regex ~r/^[^@,;\s]+@[^@,;\s]+$/

  @spec apply(Ecto.Changeset.t(), Date.t()) :: Ecto.Changeset.t()
  def apply(%Ecto.Changeset{} = changeset, today \\ Date.utc_today()) do
    changeset
    |> validate_length(:child_first_name, max: 100)
    |> validate_length(:child_last_name, max: 100)
    |> validate_length(:guardian_email, max: 160)
    |> validate_format(:guardian_email, @email_regex, message: "must be a valid email")
    # `min: 2` mirrors `Accounts.User`'s `validate_length(:name, min: 2, max: 100)`, because
    # claiming an invite builds that user's name from these two fields. Without it a CSV of
    # initials imports cleanly and dead-ends the guardian weeks later, when the row is no
    # longer in front of the person who could fix it. Guardian 2 is deliberately exempt —
    # only guardian 1 becomes a user account.
    |> validate_length(:guardian_first_name, min: 2, max: 100)
    |> validate_length(:guardian_last_name, min: 2, max: 100)
    |> validate_length(:guardian2_email, max: 160)
    |> maybe_validate_guardian2_email()
    |> validate_length(:guardian2_first_name, max: 100)
    |> validate_length(:guardian2_last_name, max: 100)
    |> validate_length(:school_name, max: 255)
    |> validate_number(:school_grade,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 13
    )
    |> validate_date_in_past(:child_date_of_birth, today)
  end

  # When guardian2_email is blank, skip the format check — a missing second
  # guardian is valid. Only a non-empty value must match the regex.
  defp maybe_validate_guardian2_email(changeset) do
    case get_field(changeset, :guardian2_email) do
      nil ->
        changeset

      "" ->
        changeset

      _ ->
        validate_format(changeset, :guardian2_email, @email_regex, message: "must be a valid email")
    end
  end

  defp validate_date_in_past(changeset, field, today) do
    validate_change(changeset, field, fn ^field, date ->
      if Date.before?(date, today) do
        []
      else
        [{field, "must be in the past"}]
      end
    end)
  end
end
