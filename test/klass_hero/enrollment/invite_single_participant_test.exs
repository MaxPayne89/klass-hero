defmodule KlassHero.Enrollment.InviteSingleParticipantTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.InviteSingleParticipant
  alias KlassHero.Repo

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Ballsports")
    %{provider: provider, program: program}
  end

  defp valid_attrs(program, overrides \\ %{}) do
    Map.merge(
      %{
        "program_id" => program.id,
        "child_first_name" => "Emma",
        "child_last_name" => "Schmidt",
        "child_date_of_birth" => "2016-03-15",
        "guardian_email" => "parent@example.com"
      },
      overrides
    )
  end

  describe "execute/2 — happy path" do
    test "persists the invite, returns its id, and drives the email pipeline", %{
      provider: provider,
      program: program
    } do
      assert {:ok, %{invite_id: invite_id}} =
               InviteSingleParticipant.execute(provider.id, valid_attrs(program))

      assert is_binary(invite_id)
      invite = Repo.get!(BulkEnrollmentInvite, invite_id)
      assert invite.program_id == program.id
      assert invite.provider_id == provider.id
      assert invite.guardian_email == "parent@example.com"
      # Trigger: downstream EnqueueInviteEmails handler runs synchronously in tests,
      # same as the CSV pipeline — the invite advances past "pending" the moment the
      # event dispatches. Matches what import_enrollment_csv_test asserts.
      assert invite.status == :invite_sent
      assert is_binary(invite.invite_token)
    end

    test "persists optional fields when provided", %{provider: provider, program: program} do
      attrs =
        valid_attrs(program, %{
          "guardian_first_name" => "Hans",
          "guardian_last_name" => "Schmidt",
          "guardian2_email" => "other@example.com",
          "school_grade" => 3,
          "school_name" => "Grundschule Mitte",
          "nut_allergy" => true,
          "consent_photo_marketing" => true
        })

      assert {:ok, %{invite_id: id}} = InviteSingleParticipant.execute(provider.id, attrs)
      invite = Repo.get!(BulkEnrollmentInvite, id)
      assert invite.school_grade == 3
      assert invite.nut_allergy == true
      assert invite.consent_photo_marketing == true
      assert invite.guardian2_email == "other@example.com"
    end
  end

  describe "execute/2 — validation failures" do
    test "returns validation_errors when required fields are blank", %{provider: provider} do
      assert {:error, %{validation_errors: errors}} =
               InviteSingleParticipant.execute(provider.id, %{})

      fields = errors |> Enum.map(fn {f, _} -> f end) |> Enum.uniq()
      assert :program_id in fields
      assert :child_first_name in fields
      assert :guardian_email in fields
      assert :child_date_of_birth in fields
    end

    test "returns validation_errors for malformed guardian email", %{
      provider: provider,
      program: program
    } do
      attrs = valid_attrs(program, %{"guardian_email" => "not-an-email"})

      assert {:error, %{validation_errors: errors}} =
               InviteSingleParticipant.execute(provider.id, attrs)

      assert {:guardian_email, "must be a valid email"} in errors
    end

    test "returns validation_errors for future date of birth", %{
      provider: provider,
      program: program
    } do
      future = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      attrs = valid_attrs(program, %{"child_date_of_birth" => future})

      assert {:error, %{validation_errors: errors}} =
               InviteSingleParticipant.execute(provider.id, attrs)

      assert Enum.any?(errors, fn {f, m} -> f == :child_date_of_birth and m =~ "past" end)
    end

    test "returns validation_errors when program_id does not belong to the provider", %{
      program: program
    } do
      # Trigger: other_provider needs at least one program so the pipeline reaches
      # authorize_program — a bare catalog short-circuits with :no_programs earlier.
      other_provider = insert(:provider_profile_schema)
      insert(:program_schema, provider_id: other_provider.id, title: "Other Program")

      assert {:error, %{validation_errors: errors}} =
               InviteSingleParticipant.execute(other_provider.id, valid_attrs(program))

      assert Enum.any?(errors, fn {f, m} ->
               f == :program_id and m =~ "does not belong"
             end)

      assert Repo.aggregate(BulkEnrollmentInvite, :count) == 0
    end
  end

  describe "execute/2 — dedup & catalog state" do
    test "returns :duplicate when the same child+email already invited to program", %{
      provider: provider,
      program: program
    } do
      assert {:ok, _} = InviteSingleParticipant.execute(provider.id, valid_attrs(program))

      # Case-insensitive on email + names to match the unique key shape
      retry =
        valid_attrs(program, %{
          "guardian_email" => "PARENT@example.com",
          "child_first_name" => "EMMA"
        })

      assert {:error, :duplicate} = InviteSingleParticipant.execute(provider.id, retry)
      assert Repo.aggregate(BulkEnrollmentInvite, :count) == 1
    end

    test "returns :no_programs when the provider has an empty catalog" do
      bare_provider = insert(:provider_profile_schema)

      assert {:error, :no_programs} =
               InviteSingleParticipant.execute(bare_provider.id, %{
                 "program_id" => Ecto.UUID.generate(),
                 "child_first_name" => "X",
                 "child_last_name" => "Y",
                 "child_date_of_birth" => "2016-01-01",
                 "guardian_email" => "x@y.com"
               })
    end
  end

  describe "execute/2 — pipeline continuity" do
    test "runs the SendInviteEmailWorker inline and tokenises the invite", %{
      provider: provider,
      program: program
    } do
      # Trigger: Oban is configured with testing: :inline, so enqueued jobs run
      # immediately. That means we can't use assert_enqueued — we verify end-state
      # instead: the invite was persisted, processed by the worker, and advanced
      # out of "pending without token" into "invite_sent" with a token.
      assert {:ok, %{invite_id: id}} =
               InviteSingleParticipant.execute(provider.id, valid_attrs(program))

      invite = Repo.get!(BulkEnrollmentInvite, id)
      assert invite.status == :invite_sent
      assert is_binary(invite.invite_token)
    end
  end
end
