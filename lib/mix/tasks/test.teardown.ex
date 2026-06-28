defmodule Mix.Tasks.Test.Teardown do
  @shortdoc "Tears down test Docker containers"

  @moduledoc """
  Tears down Docker containers after testing.

  Stops the PostgreSQL container and optionally removes it.
  By default, keeps the container and volume for faster subsequent runs.

  ## Examples

      mix test.teardown
      mix test.teardown --remove-volumes

  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: [remove_volumes: :boolean])

    Mix.shell().info([:yellow, "Tearing down test environment..."])

    case stop_containers(opts) do
      :ok ->
        Mix.shell().info([:green, "✓ Test environment cleaned up!"])

      {:error, reason} ->
        Mix.shell().error([:red, "✗ Failed to clean up test environment: #{reason}"])
        System.halt(1)
    end
  end

  defp stop_containers(opts) do
    Mix.shell().info("Stopping PostgreSQL container...")

    {compose_args, success_message} = get_compose_args_and_message(opts)

    case System.cmd("docker-compose", compose_args, stderr_to_stdout: true) do
      {_output, 0} ->
        Mix.shell().info(success_message)
        :ok

      {output, _} ->
        {:error, "Failed to stop containers: #{output}"}
    end
  end

  defp get_compose_args_and_message(opts) do
    if opts[:remove_volumes] do
      {["down", "-v"], "Container stopped and volumes removed"}
    else
      {["stop", "postgres"], "Container stopped (volumes preserved)"}
    end
  end
end
