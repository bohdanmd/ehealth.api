defmodule EHealth.Web.ContractRequestController do
  @moduledoc false

  use EHealth.Web, :controller

  alias EHealth.ContractRequests
  alias EHealth.ContractRequests.ContractRequest

  action_fallback(EHealth.Web.FallbackController)

  def index(conn, params) do
    with {:ok, paging} <- ContractRequests.search(params) do
      render(conn, "index.json", contract_requests: paging.entries, paging: paging)
    end
  end

  def create(conn, params) do
    with {:ok, %ContractRequest{} = contract_request} <- ContractRequests.create(conn.req_headers, params) do
      render(conn, "show.json", contract_request: contract_request)
    end
  end

  def update(conn, params) do
    with {:ok, %ContractRequest{} = contract_request} <- ContractRequests.update(conn.req_headers, params) do
      render(conn, "show.json", contract_request: contract_request)
    end
  end

  def show(%Plug.Conn{req_headers: headers} = conn, %{"id" => id}) do
    client_type = conn.assigns.client_type

    with {:ok, %ContractRequest{} = contract_request} <- ContractRequests.get_by_id(headers, client_type, id) do
      render(conn, "show.json", contract_request: contract_request)
    end
  end

  def approve(conn, params) do
    with {:ok, %ContractRequest{} = contract_request} <- ContractRequests.approve(conn.req_headers, params) do
      render(conn, "show.json", contract_request: contract_request)
    end
  end
end
