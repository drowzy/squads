defmodule Squads.MCP.CatalogTest do
  use ExUnit.Case, async: true

  alias Squads.MCP.Catalog

  # Note: Real tests for Catalog would need Mox for Req, 
  # but Catalog currently uses Req directly.
  # For now, we'll verify the normalization logic if we can 
  # or at least that the module compiles and has the right interface.

  test "interface exists" do
    # Catalog is likely not loaded yet in this test context if we just added it or something
    # But wait, it should be. Let's check why it fails.
    # Maybe it's because I'm using async: true and it's not fully loaded? Unlikely.
    # Let's try to load it explicitly or just check function_exported? after a small delay or ensure it's compiled.
    assert Code.ensure_loaded?(Catalog)
    assert function_exported?(Catalog, :list, 0)
    assert function_exported?(Catalog, :list, 1)
    assert function_exported?(Catalog, :refresh, 0)
  end
end
