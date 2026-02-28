Mix.Task.run("app.start")

defmodule SearchBenchmark do
  @moduledoc false

  alias JidoSkillGraph.{BenchmarkGuardrails, Snapshot}

  @default_queries ["alpha", "core", "references", "beta", "a"]
  @default_backend_mode :indexed
  @default_profile_mode :fixture
  @default_iterations 100
  @default_warmup_iterations 10
  @default_limit 20
  @profile_shapes %{
    small: %{nodes: 32, body_repetitions: 8},
    medium: %{nodes: 256, body_repetitions: 12},
    large: %{nodes: 1_024, body_repetitions: 16}
  }

  def run(args) do
    opts = parse_args(args)
    reports = run_profiles(opts)

    if opts.profile_mode == :all do
      print_profile_suite_summary(reports)
    end

    failures = BenchmarkGuardrails.evaluate(opts, reports)

    maybe_print_guardrail_summary(opts, failures)
    maybe_write_report(opts, reports, failures)

    if failures != [] do
      System.halt(2)
    end
  end

  defp parse_args(args) do
    args = normalize_args(args)

    {parsed, _, _invalid} =
      OptionParser.parse(args,
        strict: [
          root: :string,
          graph_id: :string,
          backend: :string,
          profile: :string,
          output: :string,
          min_speedup_p50: :string,
          min_speedup_p95: :string,
          max_memory_delta_mb: :string,
          enforce_profiles: :string,
          queries: :string,
          iterations: :integer,
          warmup_iterations: :integer,
          limit: :integer
        ]
      )

    root = parsed |> Keyword.get(:root, "test/fixtures/phase4/basic") |> Path.expand()
    graph_id = Keyword.get(parsed, :graph_id, "benchmark")
    backend_mode = parsed |> Keyword.get(:backend, "indexed") |> normalize_backend_mode()
    profile_mode = parsed |> Keyword.get(:profile, "fixture") |> normalize_profile_mode()
    output_path = parsed |> Keyword.get(:output) |> normalize_output_path()

    min_speedup_p50 =
      parsed |> Keyword.get(:min_speedup_p50) |> normalize_positive_threshold(:min_speedup_p50)

    min_speedup_p95 =
      parsed |> Keyword.get(:min_speedup_p95) |> normalize_positive_threshold(:min_speedup_p95)

    max_memory_delta_mb =
      parsed
      |> Keyword.get(:max_memory_delta_mb)
      |> normalize_non_negative_threshold(:max_memory_delta_mb)

    enforce_profiles =
      parsed
      |> Keyword.get(:enforce_profiles)
      |> normalize_enforce_profiles()

    iterations = max(1, Keyword.get(parsed, :iterations, @default_iterations))

    warmup_iterations =
      max(0, Keyword.get(parsed, :warmup_iterations, @default_warmup_iterations))

    limit = max(1, Keyword.get(parsed, :limit, @default_limit))

    queries =
      parsed
      |> Keyword.get(:queries, Enum.join(@default_queries, ","))
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{
      root: root,
      graph_id: graph_id,
      backend_mode: backend_mode,
      profile_mode: profile_mode,
      output_path: output_path,
      min_speedup_p50: min_speedup_p50,
      min_speedup_p95: min_speedup_p95,
      max_memory_delta_mb: max_memory_delta_mb,
      enforce_profiles: enforce_profiles,
      queries: queries,
      iterations: iterations,
      warmup_iterations: warmup_iterations,
      limit: limit
    }
  end

  defp normalize_args(["--" | rest]), do: rest
  defp normalize_args(args), do: args

  defp normalize_backend_mode(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "indexed" -> :indexed
      "basic" -> :basic
      "both" -> :both
      other -> unknown_backend_mode(other)
    end
  end

  defp normalize_backend_mode(_value), do: @default_backend_mode

  defp unknown_backend_mode(other) do
    IO.warn("unknown backend mode '#{other}', falling back to #{@default_backend_mode}")
    @default_backend_mode
  end

  defp normalize_profile_mode(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "fixture" -> :fixture
      "small" -> :small
      "medium" -> :medium
      "large" -> :large
      "all" -> :all
      other -> unknown_profile_mode(other)
    end
  end

  defp normalize_profile_mode(_value), do: @default_profile_mode

  defp normalize_output_path(nil), do: nil
  defp normalize_output_path(path) when is_binary(path), do: Path.expand(path)
  defp normalize_output_path(_path), do: nil

  defp normalize_positive_threshold(nil, _name), do: nil

  defp normalize_positive_threshold(value, name) do
    case parse_number(value) do
      {:ok, number} when number > 0.0 ->
        number

      {:ok, _number} ->
        warn_invalid_threshold(name, value, "must be > 0")
        nil

      :error ->
        warn_invalid_threshold(name, value, "must be a number")
        nil
    end
  end

  defp normalize_non_negative_threshold(nil, _name), do: nil

  defp normalize_non_negative_threshold(value, name) do
    case parse_number(value) do
      {:ok, number} when number >= 0.0 ->
        number

      {:ok, _number} ->
        warn_invalid_threshold(name, value, "must be >= 0")
        nil

      :error ->
        warn_invalid_threshold(name, value, "must be a number")
        nil
    end
  end

  defp normalize_enforce_profiles(nil), do: nil

  defp normalize_enforce_profiles(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&expand_profile_token/1)
    |> Enum.uniq()
    |> case do
      [] -> nil
      profiles -> profiles
    end
  end

  defp normalize_enforce_profiles(_value), do: nil

  defp unknown_profile_mode(other) do
    IO.warn("unknown profile '#{other}', falling back to #{@default_profile_mode}")
    @default_profile_mode
  end

  defp expand_profile_token(token) when is_binary(token) do
    case token |> String.trim() |> String.downcase() do
      "fixture" -> [:fixture]
      "small" -> [:small]
      "medium" -> [:medium]
      "large" -> [:large]
      "all" -> [:fixture, :small, :medium, :large]
      other -> warn_unknown_enforced_profile(other)
    end
  end

  defp warn_unknown_enforced_profile(profile) do
    IO.warn("unknown enforced profile '#{profile}', ignoring")
    []
  end

  defp warn_invalid_threshold(name, value, reason) do
    IO.warn("invalid #{name}=#{inspect(value)} (#{reason}), ignoring")
  end

  defp parse_number(value) when is_integer(value), do: {:ok, value / 1}
  defp parse_number(value) when is_float(value), do: {:ok, value}

  defp parse_number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp parse_number(_value), do: :error

  defp run_profiles(%{profile_mode: :all} = opts) do
    [:fixture, :small, :medium, :large]
    |> Enum.map(fn profile_mode ->
      IO.puts("\n=== profile=#{profile_mode} ===")
      run_single_profile(%{opts | profile_mode: profile_mode})
    end)
  end

  defp run_profiles(opts) do
    [run_single_profile(opts)]
  end

  defp run_single_profile(opts) do
    with_prepared_root(opts, fn prepared_opts ->
      runtime = runtime_names()
      runtime_opts = Map.merge(prepared_opts, runtime)

      {:ok, graph_pid} =
        JidoSkillGraph.start_link(
          name: runtime_opts.graph_name,
          store: [name: runtime_opts.store_name],
          loader: [
            name: runtime_opts.loader_name,
            load_on_start: false,
            builder_opts: [root: runtime_opts.root, graph_id: runtime_opts.graph_id]
          ]
        )

      try do
        memory_before = :erlang.memory(:total)

        {reload_micros, reload_result} =
          :timer.tc(fn ->
            JidoSkillGraph.reload(runtime_opts.loader_name)
          end)

        case reload_result do
          :ok ->
            :ok

          {:error, reason} ->
            raise "search benchmark reload failed: #{inspect(reason)}"

          other ->
            raise "search benchmark reload returned unexpected response: #{inspect(other)}"
        end

        snapshot = JidoSkillGraph.current_snapshot(runtime_opts.store_name)
        memory_after = :erlang.memory(:total)
        corpus_stats = summarize_corpus(snapshot, memory_before, memory_after, reload_micros)
        backend_plan = backend_plan(runtime_opts.backend_mode)

        print_run_header(runtime_opts, backend_plan, corpus_stats)

        results =
          backend_plan
          |> Enum.map(fn {backend_key, backend_module} ->
            {backend_key, benchmark_backend(runtime_opts, backend_module)}
          end)
          |> Map.new()

        print_results(runtime_opts, results)

        %{
          profile: runtime_opts.profile_mode,
          graph_id: runtime_opts.graph_id,
          root: runtime_opts.root,
          backend_mode: runtime_opts.backend_mode,
          queries: runtime_opts.queries,
          iterations: runtime_opts.iterations,
          warmup_iterations: runtime_opts.warmup_iterations,
          limit: runtime_opts.limit,
          corpus: corpus_stats,
          results: results
        }
      after
        maybe_stop_graph(graph_pid)
      end
    end)
  end

  defp runtime_names do
    %{
      graph_name: :"SearchBenchmark.Graph.#{System.unique_integer([:positive])}",
      store_name: :"SearchBenchmark.Store.#{System.unique_integer([:positive])}",
      loader_name: :"SearchBenchmark.Loader.#{System.unique_integer([:positive])}"
    }
  end

  defp maybe_stop_graph(graph_pid) when is_pid(graph_pid) do
    Supervisor.stop(graph_pid)
  catch
    :exit, _reason -> :ok
    :error, _reason -> :ok
  end

  defp with_prepared_root(%{profile_mode: :fixture} = opts, callback)
       when is_function(callback, 1) do
    callback.(opts)
  end

  defp with_prepared_root(opts, callback) when is_function(callback, 1) do
    shape = Map.fetch!(@profile_shapes, opts.profile_mode)
    generated_root = generated_root(opts.profile_mode)

    generate_synthetic_corpus(generated_root, shape.nodes, shape.body_repetitions)

    prepared_opts = %{
      opts
      | root: generated_root,
        graph_id: "#{opts.graph_id}-#{opts.profile_mode}"
    }

    try do
      callback.(prepared_opts)
    after
      _ = File.rm_rf(generated_root)
    end
  end

  defp generated_root(profile_mode) do
    Path.join(
      System.tmp_dir!(),
      "jsg_benchmark_#{profile_mode}_#{System.unique_integer([:positive])}"
    )
  end

  defp generate_synthetic_corpus(root, node_count, body_repetitions) do
    _ = File.rm_rf(root)
    :ok = File.mkdir_p(root)

    Enum.each(1..node_count, fn index ->
      node_id = synthetic_node_id(index)
      next_node_id = synthetic_node_id(rem(index, node_count) + 1)
      prev_node_id = synthetic_node_id(if(index == 1, do: node_count, else: index - 1))
      node_dir = Path.join(root, node_id)

      :ok = File.mkdir_p(node_dir)

      body =
        Enum.map_join(1..body_repetitions, " ", fn repetition ->
          token = rem(index + repetition, 64)
          "alpha core references beta benchmark token#{token}"
        end)

      contents = """
      ---
      slug: #{node_id}
      title: Benchmark #{index}
      tags:
        - benchmark
        - synthetic
      links:
        - target: #{next_node_id}
          rel: related
        - target: #{prev_node_id}
          rel: prereq
      ---
      #{body} [[#{next_node_id}]] [[related:#{prev_node_id}]]
      """

      :ok = File.write(Path.join(node_dir, "SKILL.md"), contents)
    end)
  end

  defp synthetic_node_id(index),
    do: "node-#{index |> Integer.to_string() |> String.pad_leading(4, "0")}"

  defp backend_plan(:indexed), do: [indexed: backend_module(:indexed)]
  defp backend_plan(:basic), do: [basic: backend_module(:basic)]
  defp backend_plan(:both), do: [indexed: backend_module(:indexed), basic: backend_module(:basic)]

  defp backend_module(:indexed), do: JidoSkillGraph.SearchBackend.Indexed
  defp backend_module(:basic), do: JidoSkillGraph.SearchBackend.Basic

  defp backend_labels(plan) do
    plan
    |> Enum.map_join(",", fn {backend_key, _backend_module} -> Atom.to_string(backend_key) end)
  end

  defp print_run_header(opts, backend_plan, corpus_stats) do
    IO.puts(
      "Benchmarking graph_id=#{opts.graph_id} root=#{opts.root} profile=#{opts.profile_mode}"
    )

    IO.puts("backends=#{backend_labels(backend_plan)}")

    IO.puts(
      "queries=#{Enum.join(opts.queries, ", ")} iterations=#{opts.iterations} warmup=#{opts.warmup_iterations}"
    )

    IO.puts(
      "corpus nodes=#{corpus_stats.node_count} edges=#{corpus_stats.edge_count} docs=#{corpus_stats.document_count} terms=#{corpus_stats.term_count} posting_keys=#{corpus_stats.posting_key_count} body_cache_nodes=#{corpus_stats.body_cache_nodes}"
    )

    IO.puts(
      "reload_ms=#{round_ms(corpus_stats.reload_ms)} memory_before_mb=#{round_mb(corpus_stats.memory_before_bytes)} memory_after_mb=#{round_mb(corpus_stats.memory_after_bytes)} memory_delta_mb=#{round_mb(corpus_stats.memory_delta_bytes)}"
    )
  end

  defp summarize_corpus(nil, memory_before, memory_after, reload_micros) do
    %{
      node_count: 0,
      edge_count: 0,
      document_count: 0,
      term_count: 0,
      posting_key_count: 0,
      body_cache_nodes: 0,
      memory_before_bytes: memory_before,
      memory_after_bytes: memory_after,
      memory_delta_bytes: memory_after - memory_before,
      reload_ms: reload_micros / 1_000
    }
  end

  defp summarize_corpus(snapshot, memory_before, memory_after, reload_micros) do
    search_index = snapshot.search_index
    search_meta = if search_index, do: search_index.meta, else: %{}
    body_cache_meta = if search_index, do: search_index.body_cache_meta, else: %{}

    %{
      node_count: Snapshot.node_ids(snapshot) |> length(),
      edge_count: Snapshot.edges(snapshot) |> length(),
      document_count: if(search_index, do: search_index.document_count, else: 0),
      term_count: Map.get(search_meta, :document_frequencies, %{}) |> map_size(),
      posting_key_count: Map.get(search_meta, :postings, %{}) |> map_size(),
      body_cache_nodes: Map.get(body_cache_meta, :cached_nodes, 0),
      memory_before_bytes: memory_before,
      memory_after_bytes: memory_after,
      memory_delta_bytes: memory_after - memory_before,
      reload_ms: reload_micros / 1_000
    }
  end

  defp benchmark_backend(opts, backend_module) do
    query_samples =
      Enum.into(opts.queries, %{}, fn query ->
        warmup_query(opts, query, backend_module)
        {query, run_samples(opts, query, backend_module)}
      end)

    query_stats =
      Enum.into(query_samples, %{}, fn {query, samples} ->
        {query, summarize_samples(samples)}
      end)

    overall_samples =
      query_samples
      |> Map.values()
      |> List.flatten()

    %{
      query_stats: query_stats,
      overall: summarize_samples(overall_samples)
    }
  end

  defp warmup_query(%{warmup_iterations: 0}, _query, _backend_module), do: :ok

  defp warmup_query(opts, query, backend_module) do
    Enum.each(1..opts.warmup_iterations, fn _ ->
      _ = run_query(opts, query, backend_module)
    end)
  end

  defp run_samples(opts, query, backend_module) do
    Enum.map(1..opts.iterations, fn _ ->
      run_query(opts, query, backend_module)
    end)
  end

  defp run_query(opts, query, backend_module) do
    {duration_micros, result} =
      :timer.tc(fn ->
        JidoSkillGraph.search(opts.graph_id, query,
          store: opts.store_name,
          search_backend: backend_module,
          limit: opts.limit
        )
      end)

    case result do
      {:ok, _results} -> duration_micros
      {:error, reason} -> raise "search benchmark query failed: #{inspect(reason)}"
      other -> raise "search benchmark query returned unexpected response: #{inspect(other)}"
    end
  end

  defp summarize_samples(samples) when is_list(samples) and samples != [] do
    avg_ms = samples |> Enum.sum() |> Kernel./(length(samples)) |> Kernel./(1_000)
    p50_ms = percentile(samples, 50) / 1_000
    p95_ms = percentile(samples, 95) / 1_000
    min_ms = Enum.min(samples) / 1_000
    max_ms = Enum.max(samples) / 1_000

    %{
      avg_ms: avg_ms,
      p50_ms: p50_ms,
      p95_ms: p95_ms,
      min_ms: min_ms,
      max_ms: max_ms
    }
  end

  defp print_results(opts, %{indexed: indexed_stats, basic: basic_stats}) do
    print_backend_stats("indexed", indexed_stats, opts.queries)
    print_backend_stats("basic", basic_stats, opts.queries)
    print_comparison(indexed_stats, basic_stats, opts.queries)
  end

  defp print_results(opts, %{indexed: indexed_stats}) do
    print_backend_stats("indexed", indexed_stats, opts.queries)
  end

  defp print_results(opts, %{basic: basic_stats}) do
    print_backend_stats("basic", basic_stats, opts.queries)
  end

  defp print_profile_suite_summary(reports) do
    IO.puts("\nprofile_suite_summary")

    Enum.each(reports, fn report ->
      profile = report.profile
      corpus = report.corpus
      indexed_stats = Map.get(report.results, :indexed)
      basic_stats = Map.get(report.results, :basic)

      speedup_p50 =
        if indexed_stats && basic_stats do
          speedup_ratio(basic_stats.overall.p50_ms, indexed_stats.overall.p50_ms)
        else
          "n/a"
        end

      speedup_p95 =
        if indexed_stats && basic_stats do
          speedup_ratio(basic_stats.overall.p95_ms, indexed_stats.overall.p95_ms)
        else
          "n/a"
        end

      IO.puts(
        "profile=#{profile} nodes=#{corpus.node_count} docs=#{corpus.document_count} reload_ms=#{round_ms(corpus.reload_ms)} memory_delta_mb=#{round_mb(corpus.memory_delta_bytes)} speedup_p50=#{speedup_p50} speedup_p95=#{speedup_p95}"
      )
    end)
  end

  defp maybe_print_guardrail_summary(opts, failures) do
    cond do
      not BenchmarkGuardrails.configured?(opts) ->
        :ok

      failures == [] ->
        IO.puts("\nguardrail_status=pass")
        :ok

      true ->
        IO.puts("\nguardrail_status=fail")

        Enum.each(failures, fn failure ->
          IO.puts("guardrail_failure=#{failure}")
        end)

        :ok
    end
  end

  defp maybe_write_report(%{output_path: nil}, _reports, _failures), do: :ok

  defp maybe_write_report(opts, reports, failures) do
    output_path = opts.output_path

    payload = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      options: %{
        backend_mode: opts.backend_mode,
        profile_mode: opts.profile_mode,
        iterations: opts.iterations,
        warmup_iterations: opts.warmup_iterations,
        limit: opts.limit,
        queries: opts.queries
      },
      guardrails: %{
        configured: BenchmarkGuardrails.configured?(opts),
        enforced_profiles: BenchmarkGuardrails.enforced_profiles(opts),
        min_speedup_p50: opts.min_speedup_p50,
        min_speedup_p95: opts.min_speedup_p95,
        max_memory_delta_mb: opts.max_memory_delta_mb,
        status: BenchmarkGuardrails.status(opts, failures),
        failures: failures
      },
      reports: reports
    }

    :ok = File.mkdir_p(Path.dirname(output_path))
    :ok = File.write(output_path, Jason.encode!(payload, pretty: true))
    IO.puts("\nreport_written=#{output_path}")
    :ok
  end

  defp print_backend_stats(label, stats, queries) do
    IO.puts("\nbackend=#{label}")

    Enum.each(queries, fn query ->
      query_stats = Map.fetch!(stats.query_stats, query)
      IO.puts("query=#{inspect(query)} #{format_stats(query_stats)}")
    end)

    IO.puts("overall #{format_stats(stats.overall)}")
  end

  defp print_comparison(indexed_stats, basic_stats, queries) do
    IO.puts("\ncomparison=basic/indexed speedup")

    Enum.each(queries, fn query ->
      indexed_query_stats = Map.fetch!(indexed_stats.query_stats, query)
      basic_query_stats = Map.fetch!(basic_stats.query_stats, query)

      IO.puts(
        "query=#{inspect(query)} speedup_p50=#{speedup_ratio(basic_query_stats.p50_ms, indexed_query_stats.p50_ms)} speedup_p95=#{speedup_ratio(basic_query_stats.p95_ms, indexed_query_stats.p95_ms)}"
      )
    end)

    IO.puts(
      "overall speedup_p50=#{speedup_ratio(basic_stats.overall.p50_ms, indexed_stats.overall.p50_ms)} speedup_p95=#{speedup_ratio(basic_stats.overall.p95_ms, indexed_stats.overall.p95_ms)}"
    )
  end

  defp format_stats(stats) do
    "avg_ms=#{round_ms(stats.avg_ms)} p50_ms=#{round_ms(stats.p50_ms)} p95_ms=#{round_ms(stats.p95_ms)} min_ms=#{round_ms(stats.min_ms)} max_ms=#{round_ms(stats.max_ms)}"
  end

  defp speedup_ratio(numerator_ms, denominator_ms) when denominator_ms > 0.0 do
    "#{Float.round(numerator_ms / denominator_ms, 3)}x"
  end

  defp speedup_ratio(_numerator_ms, _denominator_ms), do: "n/a"

  defp round_ms(value), do: Float.round(value, 3)
  defp round_mb(value), do: (value / 1_048_576) |> Float.round(3)

  defp percentile(samples, p) when is_list(samples) and samples != [] and is_integer(p) do
    sorted = Enum.sort(samples)
    rank = ceil(length(sorted) * (p / 100))
    Enum.at(sorted, max(rank - 1, 0))
  end
end

SearchBenchmark.run(System.argv())
