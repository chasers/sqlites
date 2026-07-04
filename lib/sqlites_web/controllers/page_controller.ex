defmodule SqlitesWeb.PageController do
  use SqlitesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
