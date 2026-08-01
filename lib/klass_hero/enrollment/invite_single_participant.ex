defmodule KlassHero.Enrollment.InviteSingleParticipant do
  @moduledoc """
  Creates one enrollment invite from a manual single-invite form submission.

  Mirrors the validate → authorise → dedup → persist → publish tail of
  `ImportEnrollmentCsv`, but for a single row with a pre-resolved
  `program_id`. Shares the same `EnqueueInviteEmails` call, which tokens every
  pending invite in the program — the new one included.
  """

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.EnqueueInviteEmails
  alias KlassHero.Enrollment.ProviderProgramContext
  alias KlassHero.Enrollment.SingleInviteForm
  alias KlassHero.Shared.ChangesetErrors

  require Logger

  @type result ::
          {:ok, %{invite_id: binary()}}
          | {:error, :no_programs}
          | {:error, :duplicate}
          | {:error, %{validation_errors: [{atom(), String.t()}]}}

  @spec execute(binary(), map()) :: result()
  def execute(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    with {:ok, context} <- provider_context(provider_id),
         {:ok, form_changeset} <- validate_form(attrs),
         {:ok, row} <- SingleInviteForm.to_invite_row(form_changeset),
         :ok <- authorize_program(row.program_id, context.programs_by_title),
         :ok <- check_duplicate(row),
         {:ok, invite} <- persist(row, provider_id) do
      enqueue_invite_email(provider_id, invite.program_id)

      Logger.info("[InviteSingleParticipant] Invite created",
        invite_id: invite.id,
        program_id: invite.program_id
      )

      {:ok, %{invite_id: invite.id}}
    end
  end

  defp provider_context(provider_id) do
    case ProviderProgramContext.for_provider(provider_id) do
      {:ok, context} ->
        {:ok, context}

      {:error, :no_programs} ->
        {:error, :no_programs}

      {:error, {:title_collisions, titles}} ->
        {:error,
         %{
           validation_errors: [
             {:program_id, "program catalog has titles differing only by case: #{Enum.join(titles, ", ")}"}
           ]
         }}
    end
  end

  defp validate_form(attrs) do
    case SingleInviteForm.changeset(attrs) do
      %Ecto.Changeset{valid?: true} = cs -> {:ok, cs}
      %Ecto.Changeset{} = cs -> {:error, %{validation_errors: ChangesetErrors.field_list(cs)}}
    end
  end

  # program_id comes from the client — verify the provider owns it before
  # we use it for anything else.
  defp authorize_program(program_id, programs_by_title) do
    if program_id in Map.values(programs_by_title) do
      :ok
    else
      {:error, %{validation_errors: [{:program_id, "program does not belong to this provider"}]}}
    end
  end

  defp check_duplicate(row) do
    if Enrollment.invite_exists?(
         row.program_id,
         row.guardian_email,
         row.child_first_name,
         row.child_last_name
       ) do
      {:error, :duplicate}
    else
      :ok
    end
  end

  defp persist(row, provider_id) do
    case Enrollment.create_invite(Map.put(row, :provider_id, provider_id)) do
      {:ok, invite} ->
        {:ok, invite}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, %{validation_errors: ChangesetErrors.field_list(changeset)}}
    end
  end

  defp enqueue_invite_email(provider_id, program_id) do
    EnqueueInviteEmails.execute([program_id], provider_id)
  end
end
