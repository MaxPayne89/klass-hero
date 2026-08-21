defmodule Mix.Tasks.Dev.Setup do
  @shortdoc "Sets up Docker containers for development"

  @moduledoc """
  Sets up Docker containers for development.

  Starts all docker-compose services (PostgreSQL, MinIO, bucket creation)
  and waits for both PostgreSQL and MinIO to be healthy before proceeding.

  ## Examples

      mix dev.setup
      mix dev.setup --force-recreate

  """
  use Mix.Task

  @postgres_container "klass_hero_postgres"
  @minio_container "klass_hero_minio"
  @max_health_check_retries 30

  @impl Mix.Task
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: [force_recreate: :boolean])

    Mix.shell().info([:green, "Setting up development environment..."])

    with :ok <- check_docker_available(),
         :ok <- start_containers(opts),
         :ok <- wait_for_postgres(),
         :ok <- wait_for_minio() do
      Mix.shell().info([:green, "Development environment ready!"])
    else
      {:error, reason} ->
        Mix.shell().error([:red, "Failed to set up development environment: #{reason}"])
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
    if containers_running?() do
      handle_already_running(opts)
    else
      Mix.shell().info("Starting containers...")
      start_compose(opts)
    end
  end

  defp containers_running? do
    postgres_running? = container_running?(@postgres_container)
    minio_running? = container_running?(@minio_container)
    postgres_running? and minio_running?
  end

  defp container_running?(name) do
    case System.cmd("docker", ["ps", "--filter", "name=#{name}", "--format", "{{.Names}}"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) == name
      _ -> false
    end
  end

  defp handle_already_running(opts) do
    if opts[:force_recreate] do
      Mix.shell().info("Force recreating containers...")
      execute_compose(["up", "-d", "--force-recreate"], "recreated", "recreate")
    else
      Mix.shell().info("Containers already running, skipping startup")
      :ok
    end
  end

  defp start_compose(opts) do
    if opts[:force_recreate] do
      execute_compose(["up", "-d", "--force-recreate"], "started", "start")
    else
      execute_compose(["up", "-d"], "started", "start")
    end
  end

  defp execute_compose(args, success_verb, failure_verb) do
    case System.cmd("docker-compose", args, stderr_to_stdout: true) do
      {_output, 0} ->
        Mix.shell().info("Containers #{success_verb} successfully")
        :ok

      {output, _} ->
        {:error, "Failed to #{failure_verb} containers: #{output}"}
    end
  end

  defp wait_for_postgres do
    Mix.shell().info("Waiting for PostgreSQL to be ready...")

    wait_for_health(@postgres_container, "PostgreSQL", @max_health_check_retries, fn ->
      System.cmd("docker", ["exec", @postgres_container, "pg_isready", "-U", "postgres"], stderr_to_stdout: true)
    end)
  end

  defp wait_for_minio do
    Mix.shell().info("Waiting for MinIO to be ready...")

    wait_for_health(@minio_container, "MinIO", @max_health_check_retries, fn ->
      System.cmd(
        "docker",
        ["inspect", "--format", "{{.State.Health.Status}}", @minio_container],
        stderr_to_stdout: true
      )
      |> case do
        {"healthy\n", 0} -> {"healthy", 0}
        other -> other
      end
    end)
  end

  defp wait_for_health(_container, service, 0, _check_fn) do
    {:error, "#{service} failed to become ready within #{@max_health_check_retries} seconds"}
  end

  defp wait_for_health(container, service, retries, check_fn) do
    case check_fn.() do
      {_, 0} ->
        Mix.shell().info([:green, "#{service} is ready"])
        :ok

      _ ->
        Process.sleep(1000)
        wait_for_health(container, service, retries - 1, check_fn)
    end
  end
end
