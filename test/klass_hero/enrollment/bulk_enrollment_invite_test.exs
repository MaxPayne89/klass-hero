defmodule KlassHero.Enrollment.BulkEnrollmentInviteTest do
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.BulkEnrollmentInvite

  describe "classify_failure/2" do
    defp tokenless, do: %BulkEnrollmentInvite{invite_token: nil}
    defp tokenful, do: %BulkEnrollmentInvite{invite_token: "test-token-123"}

    defp invalid_changeset do
      BulkEnrollmentInvite.import_changeset(%{"child_first_name" => "Emma"})
    end

    test "names the missing token whatever the reason says" do
      for reason <- [nil, :program_full, "job died", {:delivery, :timeout}, invalid_changeset()] do
        assert {:no_token, %{}} = BulkEnrollmentInvite.classify_failure(tokenless(), reason),
               "a tokenless invite reported #{inspect(reason)} as its cause instead of the missing token"
      end
    end

    test "classifies every known reason, with the detail the provider needs to act" do
      cases = [
        {:program_full, :program_full, %{}},
        {{:invalid_date, "not-a-date"}, :invalid_date, %{"value" => "not-a-date"}},
        {{:delivery, {:network, :timeout}}, :delivery_failed, %{}},
        {nil, :exhausted, %{}},
        {"** (Oban.PerformError) ... failed with {:error, :not_found}", :exhausted, %{}},
        {:some_unmapped_atom, :generic, %{}},
        {{:error, %{nested: [:deeply, {:awkwardly, "shaped"}]}}, :generic, %{}}
      ]

      for {reason, code, context} <- cases do
        assert {^code, ^context} = BulkEnrollmentInvite.classify_failure(tokenful(), reason),
               "#{inspect(reason)} was not classified as #{inspect(code)} carrying #{inspect(context)}"
      end
    end

    test "carries a changeset's fields as the details the provider has to fix" do
      assert {:invalid_details, %{"fields" => fields}} =
               BulkEnrollmentInvite.classify_failure(tokenful(), invalid_changeset())

      assert %{"field" => "child_date_of_birth", "msg" => "can't be blank"} =
               Enum.find(fields, &(&1["field"] == "child_date_of_birth"))
    end

    # A changeset can be invalid with its errors on an association rather than a field.
    # Naming no field is better than naming none convincingly.
    test "falls back to the generic cause when a changeset names no field" do
      empty = Ecto.Changeset.change(%BulkEnrollmentInvite{})

      assert {:generic, %{}} = BulkEnrollmentInvite.classify_failure(tokenful(), empty)
    end

    # The context is persisted as jsonb and read back by the component, so anything that
    # does not survive a JSON round trip is a term the provider would eventually read
    # (#1290) or a decode that would raise on the render path.
    test "builds a context that survives a JSON round trip unchanged" do
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

      for reason <- reasons do
        {_code, context} = BulkEnrollmentInvite.classify_failure(tokenful(), reason)

        assert context == context |> Jason.encode!() |> Jason.decode!(),
               "#{inspect(reason)} built a context that changes shape through jsonb: #{inspect(context)}"
      end
    end
  end
end
