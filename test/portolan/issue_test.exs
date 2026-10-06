defmodule Portolan.IssueTest do
  use ExUnit.Case, async: true

  alias Portolan.Issue

  doctest Portolan.Issue

  test "issues without position" do
    assert %Issue{line: nil} = Issue.warning("no position")
    assert %Issue{line: nil} = Issue.error("unknown line", 0)
  end

  test "put_file/2 keeps the files already set" do
    issue = %Issue{severity: :error, message: "boom", file: "a.ex"}
    assert Issue.put_file([issue], "b.ex") == [issue]
  end
end
