defmodule KlassHero.Shared.InteractionFixture do
  @moduledoc false
  use KlassHero.Shared.Interaction

  def create_ok(value) do
    db_interaction operation: :create, entity: "widget" do
      {:ok, value}
    end
  end

  def insert_changeset_error do
    db_interaction operation: :create, entity: "widget" do
      {:error, %Ecto.Changeset{errors: [name: {"can't be blank", [validation: :required]}], valid?: false}}
    end
  end

  def insert_conflict do
    db_interaction operation: :create, entity: "widget" do
      {:error, :duplicate_resource}
    end
  end

  def list_widgets do
    db_interaction operation: :list, entity: "widget" do
      [:a, :b, :c]
    end
  end

  def exists? do
    db_interaction operation: :exists, entity: "widget" do
      false
    end
  end

  def strict_get do
    db_interaction operation: :get, entity: "widget", success: &match?({:ok, _}, &1) do
      {:error, :not_found}
    end
  end

  def capture_attrs(attrs) do
    db_interaction operation: :create, entity: "child", input: attrs do
      {:ok, attrs}
    end
  end

  def boom(mode \\ :raise) do
    db_interaction operation: :create, entity: "widget" do
      # Branch so the block isn't statically total-raise (which would infer
      # none() and trip the macro's internal result binding). Real adapter
      # blocks always return a value, so they never hit this.
      if mode == :raise, do: raise(RuntimeError, "boom"), else: {:ok, mode}
    end
  end
end

defmodule KlassHero.Shared.InteractionTest do
  # async: false — telemetry handlers are global, so a concurrent module's
  # interaction events would arrive at this test's handler and cross-talk.
  use ExUnit.Case, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.Shared.InteractionFixture, as: Fixture

  setup do
    test_pid = self()
    ref = make_ref()

    events = [
      [:klass_hero, :interaction, :start],
      [:klass_hero, :interaction, :stop],
      [:klass_hero, :interaction, :exception]
    ]

    :telemetry.attach_many(
      {__MODULE__, ref},
      events,
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      %{}
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)
    :ok
  end

  describe "native return value" do
    test "is preserved unchanged — the carrier never reaches the caller" do
      assert Fixture.create_ok(:payload) == {:ok, :payload}
      assert {:error, %Ecto.Changeset{}} = Fixture.insert_changeset_error()
      assert Fixture.list_widgets() == [:a, :b, :c]
      assert Fixture.exists?() == false
      assert Fixture.strict_get() == {:error, :not_found}
    end
  end

  describe "telemetry emission" do
    test "stop event carries duration and an :ok status for a successful write" do
      Fixture.create_ok(:payload)

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], %{duration_us: us},
                      %{io_kind: :db, operation: :create, status: :ok}}

      assert is_integer(us) and us >= 0
    end

    test "stop event records row count for a bare-list read" do
      Fixture.list_widgets()

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _measurements,
                      %{status: :ok, attributes: attributes}}

      assert attributes["db.rows"] == 3
    end
  end

  describe "outcome classification" do
    test "a bare false read is a success" do
      Fixture.exists?()
      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _, %{status: :ok}}
    end

    test "a changeset error collapses to :db_error (detail lives on the span/stacktrace)" do
      Fixture.insert_changeset_error()
      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _, %{status: :error, error: :db_error}}
    end

    test "an atom error reason passes straight through" do
      Fixture.insert_conflict()
      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _, %{status: :error, error: :duplicate_resource}}
    end

    test "a per-call success: override flags an expected shape as :error" do
      Fixture.strict_get()
      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _, %{status: :error, error: :not_found}}
    end
  end

  describe "OTel span composition" do
    test "opens a span named for the adapter function with db attributes" do
      Fixture.create_ok(:payload)
      assert_span("Shared.InteractionFixture.create_ok/1", "db.entity": "widget")
    end
  end

  describe "let-it-crash" do
    test "reraises the original exception, emitting an exception event and an error span" do
      assert_raise RuntimeError, "boom", fn -> Fixture.boom() end

      assert_receive {:telemetry, [:klass_hero, :interaction, :exception], _measurements,
                      %{io_kind: :db, reason: %RuntimeError{message: "boom"}}}

      span = assert_span("Shared.InteractionFixture.boom/1")
      assert span_status_code(span) == :error
    end

    test "does not emit a stop event when the block raises" do
      catch_error(Fixture.boom())
      refute_receive {:telemetry, [:klass_hero, :interaction, :stop], _, _}
    end
  end

  describe "PII sanitisation" do
    test "drops captured input to :redacted by default" do
      Fixture.capture_attrs(%{email: "parent@example.com", child_name: "Mia"})

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _measurements, %{sanitized_input: sanitized}}

      assert sanitized == :redacted
    end

    test "never lets raw input reach telemetry metadata" do
      Fixture.capture_attrs(%{email: "parent@example.com"})

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _, metadata}
      refute inspect(metadata) =~ "parent@example.com"
    end
  end
end
