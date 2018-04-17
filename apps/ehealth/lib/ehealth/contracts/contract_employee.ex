defmodule EHealth.Contracts.ContractEmployee do
  @moduledoc false

  use Ecto.Schema
  alias Ecto.UUID
  alias EHealth.Contracts.Contract
  alias EHealth.Divisions.Division
  alias EHealth.Employees.Employee

  schema "contract_employees" do
    field(:staff_units, :float)
    field(:declaration_limit, :integer)
    field(:inserted_by, UUID)
    field(:updated_by, UUID)

    belongs_to(:employee, Employee, type: UUID)
    belongs_to(:division, Division, type: UUID)
    belongs_to(:contract, Contract, type: UUID)

    timestamps()
  end
end
