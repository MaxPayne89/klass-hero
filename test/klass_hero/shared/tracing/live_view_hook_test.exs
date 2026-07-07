defmodule KlassHero.Shared.Tracing.LiveViewHookTest do
  use ExUnit.Case, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.Shared.Tracing.LiveViewHook
  alias KlassHeroWeb.Provider.ProgramLive.Index
  alias Phoenix.LiveView.Socket

  # Span isolation (flush + drain between tests) is provided by the shared
  # `use KlassHero.TracingHelpers` setup.

  # Asserts no span with the given name was exported. Ignores unrelated spans
  # from the global OTel exporter to avoid flaky failures.
  defp refute_named_span(expected_name) do
    receive do
      {:span, s} ->
        if span(s, :name) == expected_name do
          flunk("Expected no span named #{inspect(expected_name)}, but found one")
        else
          refute_named_span(expected_name)
        end
    after
      100 -> :ok
    end
  end

  defp connected_socket(view_module, live_action \\ :index) do
    %Socket{
      transport_pid: self(),
      view: view_module,
      assigns: %{__changed__: %{}, live_action: live_action}
    }
  end

  defp disconnected_socket(view_module, live_action \\ :index) do
    %Socket{
      transport_pid: nil,
      view: view_module,
      assigns: %{__changed__: %{}, live_action: live_action}
    }
  end

  describe "on connected mount" do
    test "creates a span named from the view module" do
      socket = connected_socket(KlassHeroWeb.DashboardLive)
      {:cont, _socket} = LiveViewHook.on_mount(:trace, %{}, %{}, socket)

      assert_span("LiveView.mount DashboardLive")
    end

    test "span name strips KlassHeroWeb and KlassHero noise segments" do
      socket = connected_socket(Index)
      {:cont, _socket} = LiveViewHook.on_mount(:trace, %{}, %{}, socket)

      assert_span("LiveView.mount Provider.ProgramLive.Index")
    end

    test "sets liveview.module attribute" do
      socket = connected_socket(KlassHeroWeb.DashboardLive)
      {:cont, _socket} = LiveViewHook.on_mount(:trace, %{}, %{}, socket)

      assert_span("LiveView.mount DashboardLive", "liveview.module": "DashboardLive")
    end

    test "sets liveview.action attribute from socket assigns" do
      socket = connected_socket(KlassHeroWeb.DashboardLive, :show)
      {:cont, _socket} = LiveViewHook.on_mount(:trace, %{}, %{}, socket)

      assert_span("LiveView.mount DashboardLive", "liveview.action": "show")
    end

    test "returns {:cont, socket} unchanged" do
      socket = connected_socket(KlassHeroWeb.DashboardLive)
      assert {:cont, ^socket} = LiveViewHook.on_mount(:trace, %{}, %{}, socket)
    end

    test "span ends after mount completes (not kept open)" do
      socket = connected_socket(KlassHeroWeb.DashboardLive)
      {:cont, _socket} = LiveViewHook.on_mount(:trace, %{}, %{}, socket)

      # If span was still open it wouldn't be exported yet — finding it confirms it's ended
      assert_span("LiveView.mount DashboardLive")
    end
  end

  describe "on disconnected mount (static render)" do
    test "does not create a span" do
      socket = disconnected_socket(KlassHeroWeb.DashboardLive)
      {:cont, _socket} = LiveViewHook.on_mount(:trace, %{}, %{}, socket)

      flush_spans()
      refute_named_span("LiveView.mount DashboardLive")
    end

    test "returns {:cont, socket} unchanged" do
      socket = disconnected_socket(KlassHeroWeb.DashboardLive)
      assert {:cont, ^socket} = LiveViewHook.on_mount(:trace, %{}, %{}, socket)
    end
  end
end
