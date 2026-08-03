defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionDetailsRepositoryTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionDetailsRepository
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Repo

  defp insert_row(attrs) do
    %SessionDetail{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  describe "list_by_program/2" do
    test "returns rows ordered by session_date then start_time" do
      provider_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      insert_row(%{
        session_id: Ecto.UUID.generate(),
        program_id: program_id,
        program_title: "Judo",
        provider_id: provider_id,
        session_date: ~D[2026-05-02],
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00],
        status: :scheduled
      })

      insert_row(%{
        session_id: Ecto.UUID.generate(),
        program_id: program_id,
        program_title: "Judo",
        provider_id: provider_id,
        session_date: ~D[2026-05-01],
        start_time: ~T[15:00:00],
        end_time: ~T[16:00:00],
        status: :scheduled
      })

      [first, second] = SessionDetailsRepository.list_by_program(provider_id, program_id)

      assert %SessionDetail{session_date: ~D[2026-05-01]} = first
      assert %SessionDetail{session_date: ~D[2026-05-02]} = second
    end

    test "returns [] for unknown program" do
      assert [] == SessionDetailsRepository.list_by_program(Ecto.UUID.generate(), Ecto.UUID.generate())
    end

    test "does not leak across providers" do
      program_id = Ecto.UUID.generate()
      mine = Ecto.UUID.generate()
      theirs = Ecto.UUID.generate()

      insert_row(%{
        session_id: Ecto.UUID.generate(),
        program_id: program_id,
        program_title: "J",
        provider_id: theirs,
        session_date: ~D[2026-05-01],
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00],
        status: :scheduled
      })

      assert [] == SessionDetailsRepository.list_by_program(mine, program_id)
    end
  end

  describe "get_by_id/1" do
    test "returns {:ok, session_detail} for a known session_id" do
      provider_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()

      insert_row(%{
        session_id: session_id,
        program_id: program_id,
        program_title: "Judo",
        provider_id: provider_id,
        session_date: ~D[2026-05-01],
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00],
        status: :scheduled
      })

      assert {:ok, %SessionDetail{} = detail} = SessionDetailsRepository.get_by_id(session_id)
      assert detail.session_id == session_id
      assert detail.provider_id == provider_id
      assert detail.program_id == program_id
    end

    test "returns {:error, :not_found} for an unknown session_id" do
      assert {:error, :not_found} = SessionDetailsRepository.get_by_id(Ecto.UUID.generate())
    end
  end
end
