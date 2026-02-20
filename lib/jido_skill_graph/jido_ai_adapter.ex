defmodule JidoSkillGraph.JidoAIAdapter do
  @moduledoc """
  Optional integration helpers for JidoAI-style orchestration layers.

  This adapter wraps only public `JidoSkillGraph` APIs so consumers do not
  depend on graph internals.
  """

  alias JidoSkillGraph.SearchBackend

  @type option ::
          {:store, GenServer.name()}
          | {:tags, [String.t()]}
          | {:sort_by, :id | :title}
          | {:with_frontmatter, boolean()}
          | {:trim, boolean()}
          | {:direction, :out | :in | :both}
          | {:hops, pos_integer()}
          | {:search_backend, module()}
          | {:limit, pos_integer()}
          | {:fields, [String.t()]}
          | {:rel, JidoSkillGraph.Edge.relation() | [JidoSkillGraph.Edge.relation()]}

  @spec list_skill_candidates(String.t(), [option()]) :: {:ok, [map()]} | {:error, term()}
  def list_skill_candidates(graph_id, opts \\ []) do
    JidoSkillGraph.list_nodes(graph_id, opts)
  end

  @spec read_skill(String.t(), String.t(), [option()]) ::
          {:ok, String.t() | map()} | {:error, term()}
  def read_skill(graph_id, node_id, opts \\ []) do
    JidoSkillGraph.read_node_body(graph_id, node_id, opts)
  end

  @spec related_skills(String.t(), String.t(), [option()]) ::
          {:ok, [String.t()]} | {:error, term()}
  def related_skills(graph_id, node_id, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:direction, :out)
      |> Keyword.put_new(:hops, 1)

    JidoSkillGraph.neighbors(graph_id, node_id, opts)
  end

  @spec search_skills(String.t(), String.t(), [option()]) ::
          {:ok, [SearchBackend.result()]} | {:error, term()}
  def search_skills(graph_id, query, opts \\ []) do
    JidoSkillGraph.search(graph_id, query, opts)
  end
end
