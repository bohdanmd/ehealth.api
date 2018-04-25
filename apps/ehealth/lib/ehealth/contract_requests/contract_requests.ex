defmodule EHealth.ContractRequests do
  @moduledoc false

  use EHealth.Search, EHealth.Repo

  import Ecto.Changeset
  import Ecto.Query
  import EHealth.Utils.Connection, only: [get_consumer_id: 1, get_client_id: 1]

  alias Ecto.Adapters.SQL
  alias EHealth.ContractRequests.ContractRequest
  alias EHealth.ContractRequests.Search
  alias EHealth.Divisions.Division
  alias EHealth.Employees
  alias EHealth.Employees.Employee
  alias EHealth.LegalEntities.LegalEntity
  alias EHealth.Parties
  alias EHealth.Parties.Party
  alias EHealth.Validators.Reference
  alias EHealth.Validators.JsonSchema
  alias EHealth.Repo
  alias EHealth.Utils.NumberGenerator

  require Logger

  @mithril_api Application.get_env(:ehealth, :api_resolvers)[:mithril]

  @fields_required ~w(
    contractor_legal_entity_id
    contractor_owner_id
    contractor_base
    contractor_payment_details
    contractor_rmsp_amount
    contractor_employee_divisions
    start_date
    end_date
    id_form
    status
    inserted_by
    updated_by
    )a

  @fields_optional ~w(
    external_contractor_flag
    external_contractors
    contract_number
  )a

  def search(search_params) do
    with %Ecto.Changeset{valid?: true} = changeset <- Search.changeset(search_params),
         %Scrivener.Page{} = paging <- search(changeset, search_params, ContractRequest) do
      {:ok, paging}
    end
  end

  def create(headers, params) do
    user_id = get_consumer_id(headers)

    with {:ok, %{"data" => data}} <- @mithril_api.get_user_roles(user_id, %{}, headers),
         :ok <- JsonSchema.validate(:contract_request, params),
         :ok <- user_has_role(data, "OWNER"),
         :ok <- validate_employee_divisions(params),
         :ok <- validate_external_contractors(params),
         :ok <- validate_external_contractor_flag(params),
         :ok <- validate_start_date(params),
         :ok <- validate_end_date(params),
         :ok <- validate_contractor_owner_id(user_id, params),
         _ <- terminate_pending_contracts(params),
         insert_params <-
           params
           |> Map.put("status", ContractRequest.status(:new))
           |> Map.put("inserted_by", user_id)
           |> Map.put("updated_by", user_id),
         %Ecto.Changeset{valid?: true} = changes <- changeset(%ContractRequest{}, insert_params) do
      Repo.insert(changes)
    end
  end

  def update(headers, params) do
    user_id = get_consumer_id(headers)

    with :ok <-
           JsonSchema.validate(
             :contract_request_update,
             Map.take(params, ~w(nhs_signer_base nhs_contract_price nhs_payment_method issue_city))
           ),
         {:ok, %{"data" => data}} <- @mithril_api.get_user_roles(user_id, %{}, headers),
         :ok <- user_has_role(data, "NHS ADMIN SIGNER"),
         %ContractRequest{} = contract_request <- Repo.get(ContractRequest, params["id"]),
         :ok <- validate_status(contract_request, ContractRequest.status(:new)),
         update_params <-
           params
           |> Map.delete("id")
           |> Map.put("updated_by", user_id),
         %Ecto.Changeset{valid?: true} = changes <- update_changeset(contract_request, update_params) do
      Repo.update(changes)
    end
  end

  def approve(headers, params) do
    user_id = get_consumer_id(headers)

    with {:ok, %{"data" => data}} <- @mithril_api.get_user_roles(user_id, %{}, headers),
         :ok <- user_has_role(data, "NHS ADMIN SIGNER"),
         %ContractRequest{} = contract_request <- Repo.get(ContractRequest, params["id"]),
         :ok <- validate_status(contract_request, ContractRequest.status(:new)),
         :ok <- validate_contractor_legal_entity(contract_request),
         :ok <- validate_contractor_owner_id(user_id, contract_request),
         :ok <- validate_employee_divisions(contract_request),
         :ok <- validate_start_date(contract_request),
         update_params <-
           params
           |> Map.delete("id")
           |> Map.put("updated_by", user_id)
           |> Map.put("contract_number", get_contract_number(params))
           |> Map.put("status", ContractRequest.status(:approved)),
         %Ecto.Changeset{valid?: true} = changes <- approve_changeset(contract_request, update_params) do
      Repo.update(changes)
    end
  end

  defp get_contract_number(%{"contract_number" => contract_number}) when not is_nil(contract_number) do
    contract_number
  end

  defp get_contract_number(_) do
    with {:ok, sequence} <- get_contract_request_sequence() do
      NumberGenerator.generate_from_sequence(1, sequence)
    end
  end

  def changeset(%ContractRequest{} = contract_request, params) do
    contract_request
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
  end

  def update_changeset(%ContractRequest{} = contract_request, params) do
    contract_request
    |> cast(params, ~w(nhs_signer_base nhs_contract_price nhs_payment_method)a)
    |> validate_number(:nhs_contract_price, greater_than: 0)
  end

  def approve_changeset(%ContractRequest{} = contract_request, params) do
    fields = ~w(nhs_signer_base nhs_contract_price nhs_payment_method issue_city status)a

    contract_request
    |> cast(params, fields)
    |> validate_required(fields)
  end

  defp terminate_pending_contracts(params) do
    # TODO: add index here
    contract_ids =
      ContractRequest
      |> select([c], c.id)
      |> where([c], c.contractor_legal_entity_id == ^params["contractor_legal_entity_id"])
      |> where([c], c.id_form == ^params["id_form"])
      |> where([c], c.status in ^[ContractRequest.status(:new), ContractRequest.status(:approved)])
      |> where([c], c.end_date >= ^params["start_date"] and c.start_date <= ^params["end_date"])
      |> Repo.all()

    ContractRequest
    |> where([c], c.id in ^contract_ids)
    |> Repo.update_all(set: [status: ContractRequest.status(:terminated)])
  end

  defp user_has_role(data, role) do
    case Enum.find(data, &(Map.get(&1, "role_name") == role)) do
      nil -> {:error, :forbidden}
      _ -> :ok
    end
  end

  defp validate_employee_divisions(%ContractRequest{} = contract_request) do
    contract_request
    |> Poison.encode!()
    |> Poison.decode!()
    |> validate_employee_divisions()
  end

  defp validate_employee_divisions(params) do
    params["contractor_employee_divisions"]
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {employee_division, i}, _ ->
      with {:ok, %Employee{} = employee} <-
             Reference.validate(
               :employee,
               employee_division["employee_id"],
               "$.contractor_employee_divisions[#{i}].employee_id"
             ),
           :ok <- check_employee(employee),
           {:ok, %Division{} = division} <-
             Reference.validate(
               :division,
               employee_division["division_id"],
               "$.contractor_employee_divisions[#{i}].division_id"
             ),
           :ok <-
             check_division(
               division,
               params["contractor_legal_entity_id"],
               "$.contractor_employee_divisions[#{i}].division_id"
             ),
           :ok <- check_employee_division(employee, division, "$.contractor_employee_divisions[#{i}].employee_id") do
        {:cont, :ok}
      else
        error ->
          {:halt, error}
      end
    end)
  end

  defp validate_external_contractor_flag(%{
         "external_contractors" => external_contractors,
         "external_contractor_flag" => true
       })
       when not is_nil(external_contractors),
       do: :ok

  defp validate_external_contractor_flag(params) do
    external_contractors = Map.get(params, "external_contractors")
    external_contractor_flag = Map.get(params, "external_contractor_flag", false)

    if is_nil(external_contractors) && !external_contractor_flag do
      :ok
    else
      {:error,
       [
         {
           %{
             description: "Invalid external_contractor_flag",
             params: [],
             rule: :invalid
           },
           "$.external_contractor_flag"
         }
       ]}
    end
  end

  defp validate_external_contractors(params) do
    employee_division_ids = Enum.map(params["contractor_employee_divisions"], &Map.get(&1, "division_id"))

    params["external_contractors"]
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {contractor, i}, _ ->
      validation_result =
        contractor["divisions"]
        |> Enum.with_index()
        |> Enum.reduce_while(:ok, fn {contractor_division, j}, _ ->
          validate_external_contractor_division(
            employee_division_ids,
            contractor_division,
            "$.external_contractors[#{i}].divisions[#{j}].id"
          )
        end)

      case validation_result do
        :ok ->
          validate_external_contract(contractor, params, "$.external_contractors[#{i}].contract.expires_at")

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp validate_external_contractor_division(employee_division_ids, division, error) do
    if division["id"] in employee_division_ids do
      {:cont, :ok}
    else
      {:halt,
       {:error,
        [
          {
            %{
              description: "The division is not belong to contractor_employee_divisions",
              params: [],
              rule: :invalid
            },
            error
          }
        ]}}
    end
  end

  defp validate_external_contract(contractor, params, error) do
    expires_at = Date.from_iso8601!(contractor["contract"]["expires_at"])
    start_date = Date.from_iso8601!(params["start_date"])

    case Date.compare(expires_at, start_date) do
      :gt ->
        {:cont, :ok}

      _ ->
        {:halt,
         {:error,
          [
            {
              %{
                description: "Expires date must be greater than contract start_date",
                params: [],
                rule: :invalid
              },
              error
            }
          ]}}
    end
  end

  defp check_employee(%Employee{employee_type: "DOCTOR", status: "APPROVED", division_id: division_id})
       when not is_nil(division_id),
       do: :ok

  defp check_employee(_) do
    {:error,
     [
       {
         %{
           description: "Employee must be active DOCTOR with linked division",
           params: [],
           rule: :invalid
         },
         "$.contractor_employee_divisions.employee_id"
       }
     ]}
  end

  defp check_division(%Division{status: "ACTIVE", legal_entity_id: legal_entity_id}, contractor_legal_entity_id, _)
       when legal_entity_id == contractor_legal_entity_id,
       do: :ok

  defp check_division(_, _, error) do
    {:error,
     [
       {
         %{
           description: "Division must be active and within current legal_entity",
           params: [],
           rule: :invalid
         },
         error
       }
     ]}
  end

  defp check_employee_division(%Employee{division_id: division_id}, %Division{id: id}, _) when division_id == id,
    do: :ok

  defp check_employee_division(_, _, error) do
    {:error,
     [
       {
         %{
           description: "Employee must be within current division",
           params: [],
           rule: :invalid
         },
         error
       }
     ]}
  end

  defp validate_end_date(%{"start_date" => start_date, "end_date" => end_date}) do
    start_date = Date.from_iso8601!(start_date)
    end_date = Date.from_iso8601!(end_date)

    if start_date.year == end_date.year do
      :ok
    else
      {:error,
       [
         {
           %{
             description: "The year of start_date and and date must be equal",
             params: [],
             rule: :invalid
           },
           "$.end_date"
         }
       ]}
    end
  end

  defp validate_contractor_owner_id(user_id, %ContractRequest{
         contractor_owner_id: contractor_owner_id,
         contractor_legal_entity_id: contractor_legal_entity_id
       }) do
    validate_contractor_owner_id(user_id, %{
      "contractor_owner_id" => contractor_owner_id,
      "contractor_legal_entity_id" => contractor_legal_entity_id
    })
  end

  defp validate_contractor_owner_id(user_id, %{
         "contractor_owner_id" => contract_owner_id,
         "contractor_legal_entity_id" => contractor_legal_entity_id
       }) do
    with %Party{id: id} <- Parties.get_by_user_id(user_id),
         %{entries: [_employee]} <-
           Employees.list(%{
             "party_id" => id,
             "legal_entity_id" => contractor_legal_entity_id,
             "employee_type" => Employee.type(:owner),
             "ids" => contract_owner_id,
             "status" => Employee.status(:approved)
           }) do
      :ok
    else
      _ ->
        {:error,
         [
           {
             %{
               description: "Contractor owner must be active within current legal entity in contract request",
               params: [],
               rule: :invalid
             },
             "$.contractor_owner_id"
           }
         ]}
    end
  end

  defp validate_start_date(%ContractRequest{} = contract_request) do
    contract_request
    |> Poison.encode!()
    |> Poison.decode!()
    |> validate_start_date()
  end

  defp validate_start_date(%{"start_date" => start_date}) do
    now = Date.utc_today()
    start_date = Date.from_iso8601!(start_date)
    year_diff = start_date.year - now.year

    with {:diff, true} <- {:diff, year_diff >= 0 && year_diff <= 1},
         {:future, true} <- {:future, Date.compare(start_date, now) == :gt} do
      :ok
    else
      {:diff, false} ->
        {:error,
         [
           {
             %{
               description: "Start date must be within this or next year",
               params: [],
               rule: :invalid
             },
             "$.start_date"
           }
         ]}

      {:future, false} ->
        {:error,
         [
           {
             %{
               description: "Start date must be greater than create date",
               params: [],
               rule: :invalid
             },
             "$.start_date"
           }
         ]}
    end
  end

  defp validate_status(%ContractRequest{status: status}, required_status) when status == required_status, do: :ok
  defp validate_status(_, _), do: {:error, {:"422", "Incorrect status of contract_request to modify it"}}

  def get_by_id(headers, client_type, id) do
    client_id = get_client_id(headers)

    with {:ok, %ContractRequest{} = contract_request} <- get_contract_request(client_id, client_type, id) do
      {:ok, contract_request}
    end
  end

  defp get_contract_request(_, "NHS ADMIN", id) do
    with %ContractRequest{} = contract_request <- Repo.get(ContractRequest, id) do
      {:ok, contract_request}
    end
  end

  defp get_contract_request(client_id, "MSP", id) do
    with %ContractRequest{} = contract_request <- Repo.get(ContractRequest, id),
         :ok <- validate_legal_entity_id(contract_request, client_id) do
      {:ok, contract_request}
    end
  end

  defp validate_legal_entity_id(%ContractRequest{contractor_legal_entity_id: id}, legal_entity_id) do
    if id == legal_entity_id do
      :ok
    else
      {:error, {:forbidden, "You are not allowed to view this contract request"}}
    end
  end

  defp validate_contractor_legal_entity(%ContractRequest{contractor_legal_entity_id: legal_entity_id}) do
    with {:ok, legal_entity} <- Reference.validate(:legal_entity, legal_entity_id, "$.contractor_legal_entity_id"),
         true <- legal_entity.status == LegalEntity.status(:active) do
      :ok
    else
      false ->
        {:error,
         [
           {
             %{
               description: "Legal entity in contract request should be active",
               params: [],
               rule: :invalid
             },
             "$.contractor_legal_entity_id"
           }
         ]}

      error ->
        error
    end
  end

  defp get_contract_request_sequence do
    case SQL.query(Repo, "SELECT nextval('contract_request');", []) do
      {:ok, %Postgrex.Result{rows: [[sequence]]}} ->
        {:ok, sequence}

      _ ->
        Logger.error("Can't get contract_request sequence")
        {:error, %{"type" => "internal_error"}}
    end
  end
end
