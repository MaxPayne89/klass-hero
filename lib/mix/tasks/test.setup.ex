defmodule Mix.Tasks.Test.Setup do
  @shortdoc "Sets up Docker containers for testing"

  @moduledoc """
  Sets up Docker containers for testing.

  Ensures PostgreSQL container is running and healthy before tests run.
  Uses the existing docker-compose.yml configuration.

  ## Examples

      mix test.setup
      mix test.setup --force-recreate

  """
  use Mix.Task

  @container_name "klass_hero_postgres"
  @service_name "postgres"
  @max_health_check_retries 30

  @impl Mix.Task
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: [force_recreate: :boolean])

    Mix.shell().info([:green, "Setting up test environment..."])

    with :ok <- check_docker_available(),
         :ok <- start_containers(opts),
         :ok <- wait_for_database() do
      Mix.shell().info([:green, "✓ Test environment ready!"])
    else
      {:error, reason} ->
        Mix.shell().error([:red, "✗ Failed to set up test environment: #{reason}"])
        System.halt(1)
    end
  end

  defp check_docker_available do
    case System.cmd("docker", ["--version"], stderr_to_stdout: true) do
      {_, 0} ->
        case System.cmd("docker-compose", ["--version"], stderr_to_stdout: true) do
          {_, 0} -> :ok
          _ -> {:error, "docker-compose not available. Please install Docker Desktop."}
        end

      _ ->
        {:error, "Docker not available. Please install and start Docker Desktop."}
    end
  end

  defp start_containers(opts) do
    Mix.shell().info("Starting PostgreSQL container...")

    case check_container_running() do
      :running ->
        handle_container_already_running(opts)

      :not_running ->
        Mix.shell().info("Starting container...")
        start_compose_normal()
    end
  end

  defp check_container_running do
    docker_ps_command = build_docker_ps_command()

    case System.cmd("docker", docker_ps_command, stderr_to_stdout: true) do
      {@container_name <> "\n", 0} -> :running
      _ -> :not_running
    end
  end

  defp build_docker_ps_command do
    ["ps", "--filter", "name=#{@container_name}", "--format", "{{.Names}}"]
  end

  defp handle_container_already_running(opts) do
    if opts[:force_recreate] do
      Mix.shell().info("Force recreating container...")
      start_compose_with_force()
    else
      Mix.shell().info("Container already running, skipping startup")
      :ok
    end
  end

  defp wait_for_database do
    Mix.shell().info("Waiting for PostgreSQL to be ready...")
    wait_for_health_check(@max_health_check_retries)
  end

  defp wait_for_health_check(0) do
    {:error, "Database failed to become ready within #{@max_health_check_retries} seconds"}
  end

  defp wait_for_health_check(retries) do
    health_check_command = build_health_check_command()

    case System.cmd("docker", health_check_command, stderr_to_stdout: true) do
      {_, 0} ->
        Mix.shell().info([:green, "✓ PostgreSQL is ready"])
        :ok

      _ ->
        Process.sleep(1000)
        wait_for_health_check(retries - 1)
    end
  end

  defp build_health_check_command do
    ["exec", @container_name, "pg_isready", "-U", "postgres"]
  end

  defp start_compose_with_force do
    compose_args = ["up", "-d", "--force-recreate", @service_name]
    execute_compose_command(compose_args, "recreated", "recreate")
  end

  defp start_compose_normal do
    compose_args = ["up", "-d", @service_name]
    execute_compose_command(compose_args, "started", "start")
  end

  defp execute_compose_command(args, success_verb, failure_verb) do
    case System.cmd("docker-compose", args, stderr_to_stdout: true) do
      {_output, 0} ->
        Mix.shell().info("Container #{success_verb} successfully")
        :ok

      {output, _} ->
        {:error, "Failed to #{failure_verb} container: #{output}"}
    end
  end
end
