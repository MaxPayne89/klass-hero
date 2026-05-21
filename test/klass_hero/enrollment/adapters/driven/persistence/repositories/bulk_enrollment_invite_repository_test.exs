defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepositoryTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepository
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema
  alias KlassHero.Repo

  defp setup_program(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    %{provider: provider, program: program}
  end

  defp valid_invite_attrs(program, provider, overrides \\ %{}) do
    Map.merge(
      %{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        guardian_email: "parent@example.com"
      },
      overrides
    )
  end

  describe "create_one/1" do
    setup :setup_program

    test "inserts a single row and returns the persisted domain struct", %{
      program: program,
      provider: provider
    } do
      attrs = valid_invite_attrs(program, provider)

      assert {:ok, invite} = BulkEnrollmentInviteRepository.create_one(attrs)
      assert is_binary(invite.id)
      assert invite.program_id == program.id
      assert invite.provider_id == provider.id
      assert invite.guardian_email == "parent@example.com"
      assert invite.status == :pending
      assert Repo.aggregate(BulkEnrollmentInviteSchema, :count) == 1
    end

    test "returns {:error, changeset} when required fields are missing", %{
      program: program,
      provider: provider
    } do
      attrs = valid_invite_attrs(program, provider, %{child_last_name: nil})

      assert {:error, %Ecto.Changeset{valid?: false} = changeset} =
               BulkEnrollmentInviteRepository.create_one(attrs)

      assert %{child_last_name: ["can't be blank"]} = errors_on(changeset)
      assert Repo.aggregate(BulkEnrollmentInviteSchema, :count) == 0
    end

    test "rejects duplicate (program, email, first, last) via unique constraint", %{
      program: program,
      provider: provider
    } do
      attrs = valid_invite_attrs(program, provider)
      assert {:ok, _} = BulkEnrollmentInviteRepository.create_one(attrs)

      assert {:error, %Ecto.Changeset{valid?: false}} =
               BulkEnrollmentInviteRepository.create_one(attrs)

      assert Repo.aggregate(BulkEnrollmentInviteSchema, :count) == 1
    end

    test "persists all optional fields", %{program: program, provider: provider} do
      attrs =
        valid_invite_attrs(program, provider, %{
          guardian_first_name: "Hans",
          guardian_last_name: "Schmidt",
          guardian2_email: "other-parent@example.com",
          guardian2_first_name: "Maria",
          guardian2_last_name: "Schmidt",
          school_grade: 3,
          school_name: "Grundschule Mitte",
          medical_conditions: "Asthma",
          nut_allergy: true,
          consent_photo_marketing: true,
          consent_photo_social_media: false
        })

      assert {:ok, _} = BulkEnrollmentInviteRepository.create_one(attrs)

      invite = Repo.one!(BulkEnrollmentInviteSchema)
      assert invite.guardian_first_name == "Hans"
      assert invite.school_grade == 3
      assert invite.nut_allergy == true
      assert invite.consent_photo_marketing == true
      assert invite.status == :pending
    end
  end

  describe "invite_exists?/4" do
    setup :setup_program

    test "returns false when no invite exists", %{program: program} do
      refute BulkEnrollmentInviteRepository.invite_exists?(
               program.id,
               "new@example.com",
               "Emma",
               "Schmidt"
             )
    end

    test "returns true for an exact-case-insensitive match", %{
      program: program,
      provider: provider
    } do
      {:ok, _} = BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      assert BulkEnrollmentInviteRepository.invite_exists?(
               program.id,
               "PARENT@example.com",
               "emma",
               "SCHMIDT"
             )
    end

    test "returns false for the same names under a different program_id", %{
      program: program,
      provider: provider
    } do
      other_program = insert(:program_schema, provider_id: provider.id, title: "Other")
      {:ok, _} = BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      refute BulkEnrollmentInviteRepository.invite_exists?(
               other_program.id,
               "parent@example.com",
               "Emma",
               "Schmidt"
             )
    end
  end

  describe "list_existing_keys_for_programs/1" do
    setup :setup_program

    test "returns MapSet of existing keys", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(
          valid_invite_attrs(program, provider, %{
            child_first_name: "Emma",
            child_last_name: "Schmidt",
            guardian_email: "Parent@Example.com"
          })
        )

      result = BulkEnrollmentInviteRepository.list_existing_keys_for_programs([program.id])

      assert MapSet.size(result) == 1

      # Trigger: email and names are lowercased in the MapSet
      # Why: case-insensitive duplicate detection
      # Outcome: callers can compare normalized keys
      assert MapSet.member?(result, {program.id, "parent@example.com", "emma", "schmidt"})
    end

    test "returns empty MapSet when no matching programs exist" do
      non_existent_id = Ecto.UUID.generate()
      result = BulkEnrollmentInviteRepository.list_existing_keys_for_programs([non_existent_id])
      assert MapSet.size(result) == 0
    end

    test "returns empty MapSet for empty list" do
      result = BulkEnrollmentInviteRepository.list_existing_keys_for_programs([])
      assert result == MapSet.new()
    end

    test "includes keys from multiple programs", %{provider: provider} do
      program_a = insert(:program_schema, provider_id: provider.id)
      program_b = insert(:program_schema, provider_id: provider.id)

      rows = [
        valid_invite_attrs(program_a, provider, %{
          child_first_name: "Anna",
          guardian_email: "a@test.com"
        }),
        valid_invite_attrs(program_b, provider, %{
          child_first_name: "Ben",
          guardian_email: "b@test.com"
        })
      ]

      Enum.each(rows, &BulkEnrollmentInviteRepository.create_one/1)

      result =
        BulkEnrollmentInviteRepository.list_existing_keys_for_programs([
          program_a.id,
          program_b.id
        ])

      assert MapSet.size(result) == 2
      assert MapSet.member?(result, {program_a.id, "a@test.com", "anna", "schmidt"})
      assert MapSet.member?(result, {program_b.id, "b@test.com", "ben", "schmidt"})
    end
  end

  describe "get_by_id/1" do
    setup :setup_program

    test "returns {:ok, invite} when found", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      invite = Repo.one!(BulkEnrollmentInviteSchema)

      assert {:ok, result} = BulkEnrollmentInviteRepository.get_by_id(invite.id)
      assert result.id == invite.id
      assert result.guardian_email == "parent@example.com"
    end

    test "returns {:error, :not_found} when not found" do
      assert {:error, :not_found} =
               BulkEnrollmentInviteRepository.get_by_id(Ecto.UUID.generate())
    end
  end

  describe "list_pending_without_token/1" do
    setup :setup_program

    test "returns pending invites with no token", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      result = BulkEnrollmentInviteRepository.list_pending_without_token([program.id])
      assert length(result) == 1
      assert hd(result).status == :pending
      assert hd(result).invite_token == nil
    end

    test "excludes invites that already have tokens", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      invite = Repo.one!(BulkEnrollmentInviteSchema)
      invite |> Ecto.Changeset.change(%{invite_token: "existing-token"}) |> Repo.update!()

      assert BulkEnrollmentInviteRepository.list_pending_without_token([program.id]) == []
    end

    test "excludes non-pending invites", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      invite = Repo.one!(BulkEnrollmentInviteSchema)

      invite
      |> BulkEnrollmentInviteSchema.transition_changeset(%{
        status: :failed,
        error_details: "test"
      })
      |> Repo.update!()

      assert BulkEnrollmentInviteRepository.list_pending_without_token([program.id]) == []
    end

    test "returns empty list for empty program_ids" do
      assert BulkEnrollmentInviteRepository.list_pending_without_token([]) == []
    end
  end

  describe "bulk_assign_tokens/1" do
    setup :setup_program

    test "assigns tokens to invites", %{program: program, provider: provider} do
      rows = [
        valid_invite_attrs(program, provider),
        valid_invite_attrs(program, provider, %{
          child_first_name: "Liam",
          guardian_email: "b@test.com"
        })
      ]

      Enum.each(rows, &BulkEnrollmentInviteRepository.create_one/1)
      invites = Repo.all(BulkEnrollmentInviteSchema)
      pairs = Enum.map(invites, fn inv -> {inv.id, "token-#{inv.id}"} end)

      assert {:ok, 2} = BulkEnrollmentInviteRepository.bulk_assign_tokens(pairs)

      updated = Repo.all(BulkEnrollmentInviteSchema)
      assert Enum.all?(updated, fn inv -> inv.invite_token != nil end)
    end

    test "returns {:ok, 0} for empty list" do
      assert {:ok, 0} = BulkEnrollmentInviteRepository.bulk_assign_tokens([])
    end
  end

  describe "get_by_token/1" do
    setup :setup_program

    test "returns {:ok, invite} when token matches", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      invite = Repo.one!(BulkEnrollmentInviteSchema)
      token = "test-token-#{System.unique_integer()}"
      invite |> Ecto.Changeset.change(%{invite_token: token}) |> Repo.update!()

      assert {:ok, result} = BulkEnrollmentInviteRepository.get_by_token(token)
      assert result.id == invite.id
      assert result.invite_token == token
    end

    test "returns {:error, :not_found} when token not found" do
      assert {:error, :not_found} = BulkEnrollmentInviteRepository.get_by_token("nonexistent")
    end

    test "returns {:error, :not_found} for nil token" do
      assert {:error, :not_found} = BulkEnrollmentInviteRepository.get_by_token(nil)
    end
  end

  describe "list_by_program/1" do
    setup :setup_program

    test "returns invites for a program ordered by child_last_name", %{
      program: program,
      provider: provider
    } do
      Enum.each(
        [
          valid_invite_attrs(program, provider, %{
            child_last_name: "Zebra",
            child_first_name: "Alice",
            guardian_email: "alice@test.com"
          }),
          valid_invite_attrs(program, provider, %{
            child_last_name: "Adams",
            child_first_name: "Bob",
            guardian_email: "bob@test.com"
          })
        ],
        &BulkEnrollmentInviteRepository.create_one/1
      )

      invites = BulkEnrollmentInviteRepository.list_by_program(program.id)

      assert length(invites) == 2
      assert [first, second] = invites
      assert first.child_last_name == "Adams"
      assert second.child_last_name == "Zebra"
    end

    test "returns empty list for program with no invites" do
      assert BulkEnrollmentInviteRepository.list_by_program(Ecto.UUID.generate()) == []
    end

    test "does not return invites from other programs", %{provider: provider} do
      program_a = insert(:program_schema, provider_id: provider.id)
      program_b = insert(:program_schema, provider_id: provider.id)

      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(
          valid_invite_attrs(program_a, provider, %{
            child_last_name: "Smith",
            child_first_name: "Jane",
            guardian_email: "jane@test.com"
          })
        )

      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(
          valid_invite_attrs(program_b, provider, %{
            child_last_name: "Jones",
            child_first_name: "Tom",
            guardian_email: "tom@test.com"
          })
        )

      invites = BulkEnrollmentInviteRepository.list_by_program(program_a.id)

      assert length(invites) == 1
      assert hd(invites).child_last_name == "Smith"
    end
  end

  describe "count_by_program/1" do
    setup :setup_program

    test "returns count of invites for a program", %{program: program, provider: provider} do
      Enum.each(
        [
          valid_invite_attrs(program, provider, %{
            child_last_name: "Smith",
            child_first_name: "Jane",
            guardian_email: "jane@test.com"
          }),
          valid_invite_attrs(program, provider, %{
            child_last_name: "Jones",
            child_first_name: "Tom",
            guardian_email: "tom@test.com"
          })
        ],
        &BulkEnrollmentInviteRepository.create_one/1
      )

      assert BulkEnrollmentInviteRepository.count_by_program(program.id) == 2
    end

    test "returns 0 for program with no invites" do
      assert BulkEnrollmentInviteRepository.count_by_program(Ecto.UUID.generate()) == 0
    end
  end

  describe "delete/1" do
    setup :setup_program

    test "deletes an invite by id", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      [invite] = BulkEnrollmentInviteRepository.list_by_program(program.id)

      assert :ok = BulkEnrollmentInviteRepository.delete(invite.id)
      assert BulkEnrollmentInviteRepository.list_by_program(program.id) == []
    end

    test "returns error for non-existent invite" do
      assert {:error, :not_found} = BulkEnrollmentInviteRepository.delete(Ecto.UUID.generate())
    end
  end

  describe "reset_for_resend/1" do
    setup :setup_program

    test "resets invite_sent invite to pending with cleared token", %{
      program: program,
      provider: provider
    } do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(
          valid_invite_attrs(program, provider, %{
            child_last_name: "Smith",
            child_first_name: "Jane",
            guardian_email: "jane@test.com"
          })
        )

      [invite] = BulkEnrollmentInviteRepository.list_by_program(program.id)

      # Transition to invite_sent with a token
      {:ok, sent} =
        BulkEnrollmentInviteRepository.transition_status(invite, %{
          status: :invite_sent,
          invite_token: "test-token-123",
          invite_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert sent.status == :invite_sent

      {:ok, reset} = BulkEnrollmentInviteRepository.reset_for_resend(sent)

      assert reset.status == :pending
      assert is_nil(reset.invite_token)
      assert is_nil(reset.invite_sent_at)
    end

    test "resets failed invite to pending", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(
          valid_invite_attrs(program, provider, %{
            child_last_name: "Smith",
            child_first_name: "Jane",
            guardian_email: "jane@test.com"
          })
        )

      [invite] = BulkEnrollmentInviteRepository.list_by_program(program.id)

      {:ok, failed} =
        BulkEnrollmentInviteRepository.transition_status(invite, %{
          status: :failed,
          error_details: "delivery error"
        })

      {:ok, reset} = BulkEnrollmentInviteRepository.reset_for_resend(failed)

      assert reset.status == :pending
      assert is_nil(reset.invite_token)
      assert is_nil(reset.error_details)
    end

    test "rejects reset for registered invite", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(
          valid_invite_attrs(program, provider, %{
            child_last_name: "Smith",
            child_first_name: "Jane",
            guardian_email: "jane@test.com"
          })
        )

      [invite] = BulkEnrollmentInviteRepository.list_by_program(program.id)

      # Walk through the state machine to registered (a non-resendable status)
      {:ok, sent} =
        BulkEnrollmentInviteRepository.transition_status(invite, %{
          status: :invite_sent,
          invite_token: "tok",
          invite_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, registered} =
        BulkEnrollmentInviteRepository.transition_status(sent, %{
          status: :registered,
          registered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:error, :not_resendable} =
               BulkEnrollmentInviteRepository.reset_for_resend(registered)
    end

    test "rejects reset for enrolled invite", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(
          valid_invite_attrs(program, provider, %{
            child_last_name: "Smith",
            child_first_name: "Jane",
            guardian_email: "jane@test.com"
          })
        )

      [invite] = BulkEnrollmentInviteRepository.list_by_program(program.id)

      # Walk through the state machine: pending → invite_sent → registered → enrolled
      {:ok, sent} =
        BulkEnrollmentInviteRepository.transition_status(invite, %{
          status: :invite_sent,
          invite_token: "tok",
          invite_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, registered} =
        BulkEnrollmentInviteRepository.transition_status(sent, %{
          status: :registered,
          registered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, enrolled} =
        BulkEnrollmentInviteRepository.transition_status(registered, %{
          status: :enrolled,
          enrolled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:error, :not_resendable} =
               BulkEnrollmentInviteRepository.reset_for_resend(enrolled)
    end

    test "returns error for non-existent invite" do
      fake = %{id: Ecto.UUID.generate(), status: :pending}
      assert {:error, :not_found} = BulkEnrollmentInviteRepository.reset_for_resend(fake)
    end
  end

  describe "transition_status/2" do
    setup :setup_program

    test "transitions pending to invite_sent", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      invite = Repo.one!(BulkEnrollmentInviteSchema)

      assert {:ok, updated} =
               BulkEnrollmentInviteRepository.transition_status(invite, %{
                 status: :invite_sent,
                 invite_token: "test-token",
                 invite_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })

      assert updated.status == :invite_sent
      assert updated.invite_token == "test-token"
      assert updated.invite_sent_at != nil
    end

    test "transitions pending to failed", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      invite = Repo.one!(BulkEnrollmentInviteSchema)

      assert {:ok, updated} =
               BulkEnrollmentInviteRepository.transition_status(invite, %{
                 status: :failed,
                 error_details: "delivery failed"
               })

      assert updated.status == :failed
      assert updated.error_details == "delivery failed"
    end

    test "rejects invalid transition", %{program: program, provider: provider} do
      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(valid_invite_attrs(program, provider))

      invite = Repo.one!(BulkEnrollmentInviteSchema)

      assert {:error, %Ecto.Changeset{}} =
               BulkEnrollmentInviteRepository.transition_status(invite, %{status: :enrolled})
    end
  end
end
