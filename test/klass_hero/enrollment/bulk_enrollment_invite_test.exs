defmodule KlassHero.Enrollment.BulkEnrollmentInviteTest do
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.BulkEnrollmentInvite

  describe "describe_failure/2" do
    # Everything here is read by a provider in the invites table, so the one property
    # that must hold for every clause is that no Elixir term survives into it (#1290).
    @developer_shapes [~r/#Ecto\.Changeset/, ~r/%\{/, ~r/\{:/, ~r/\[\{/]

    defp tokenless, do: %BulkEnrollmentInvite{invite_token: nil}
    defp tokenful, do: %BulkEnrollmentInvite{invite_token: "test-token-123"}

    defp invalid_changeset do
      BulkEnrollmentInvite.import_changeset(%{"child_first_name" => "Emma"})
    end

    test "names the missing token whatever the reason says" do
      for reason <- [nil, :program_full, "job died", {:delivery, :timeout}, invalid_changeset()] do
        assert BulkEnrollmentInvite.describe_failure(tokenless(), reason) =~ "no token",
               "a tokenless invite reported #{inspect(reason)} as its cause instead of the missing token"
      end
    end

    test "turns a changeset into the fields the provider has to fix" do
      details = BulkEnrollmentInvite.describe_failure(tokenful(), invalid_changeset())

      assert details =~ "child date of birth"
      assert details =~ "can't be blank"
    end

    test "renders every known reason as a sentence" do
      cases = [
        {:program_full, "full"},
        {{:invalid_date, "not-a-date"}, "not-a-date"},
        {{:delivery, {:network, :timeout}}, "deliver"},
        {nil, "no retries remain"},
        {"** (Oban.PerformError) ... failed with {:error, :not_found}", "no retries remain"},
        {:some_unmapped_atom, "could not be completed"}
      ]

      for {reason, expected} <- cases do
        assert BulkEnrollmentInvite.describe_failure(tokenful(), reason) =~ expected,
               "#{inspect(reason)} did not render a reason containing #{inspect(expected)}"
      end
    end

    # The sweep can only hand back Oban's own error text, which is developer copy by
    # construction — passing it through would reopen the leak this function closes.
    test "never leaks a developer term, whatever it is handed" do
      reasons = [
        nil,
        :program_full,
        :some_unmapped_atom,
        {:invalid_date, "not-a-date"},
        {:invalid_date_type, %{}},
        {:delivery, {:network, :timeout}},
        {:error, %{nested: [:deeply, {:awkwardly, "shaped"}]}},
        "** (Oban.PerformError) MyWorker failed with {:error, %Ecto.Changeset{}}",
        invalid_changeset()
      ]

      for reason <- reasons, pattern <- @developer_shapes do
        details = BulkEnrollmentInvite.describe_failure(tokenful(), reason)

        refute details =~ pattern,
               "#{inspect(reason)} leaked #{inspect(pattern)} into what a provider reads: #{details}"
      end
    end
  end
end
