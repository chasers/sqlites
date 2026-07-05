defmodule SmolsqlsWeb.Api.QueryJSON do
  def show(%{result: result}) do
    %{
      data: %{
        columns: result.columns,
        rows: result.rows,
        num_changes: result.num_changes
      }
    }
  end
end
