defmodule JidoSkillGraph.SearchIndexTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.SearchIndex

  test "new/1 builds normalized index metadata" do
    assert {:ok, index} =
             SearchIndex.new(
               build_version: 2,
               document_count: 3,
               avg_field_lengths: %{
                 "id" => 1,
                 "title" => 3.5,
                 "tags" => 2,
                 "body" => 50
               },
               body_cache_meta: %{enabled: true, max_bytes_per_node: 256, cached_nodes: 2},
               meta: %{source: :test}
             )

    assert index.build_version == 2
    assert index.document_count == 3
    assert index.avg_field_lengths.id == 1.0
    assert_in_delta(index.avg_field_lengths.title, 3.5, 0.0001)
    assert index.body_cache_meta.enabled
    assert index.meta == %{source: :test}
  end

  test "from_field_lengths/2 computes averages and document count" do
    docs = %{
      "alpha" => %{id: 1, title: 2, tags: 2, body: 10},
      "beta" => %{id: 1, title: 4, tags: 0, body: 30}
    }

    assert {:ok, index} = SearchIndex.from_field_lengths(docs, build_version: 1)
    assert index.document_count == 2
    assert_in_delta(index.avg_field_lengths.id, 1.0, 0.0001)
    assert_in_delta(index.avg_field_lengths.title, 3.0, 0.0001)
    assert_in_delta(index.avg_field_lengths.tags, 1.0, 0.0001)
    assert_in_delta(index.avg_field_lengths.body, 20.0, 0.0001)
  end

  test "new/1 rejects invalid field averages" do
    assert {:error, {:invalid_avg_field_length, :title, -1}} =
             SearchIndex.new(avg_field_lengths: %{id: 1.0, title: -1, tags: 0.0, body: 0.0})
  end
end
