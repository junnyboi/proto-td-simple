class_name CampaignDef
extends Resource

## P16 strategic campaign bootstrap data. Runtime model code owns no starter,
## economy, or paid-offer tuning values.

const P16_ENVIRONMENT_SHA256 := \
	"3f90e0a63147c5ca092dad8e83feffffe2204bd57dbe601d768b4a6d6f0d9eff"
const P16_V3_ENVIRONMENT_SHA256 := \
	"2ed4cbb53592ae9fe98434667f091a00f2d97134187138e364280e9896209b90"

@export var schema_version: int = 2
@export var name_version: int = 1
@export var initial_marks: int = 0
@export var starter_operator_ids: Array[StringName] = []
@export var paid_offers: Array[Dictionary] = []
@export var environment_sha256: String = ""
## CampaignSave v3 additions. V1/v2 resources omit these fields and retain
## their exact legacy semantics.
@export var starter_rows: Array[Dictionary] = []
@export var starting_class_ids: Array[StringName] = []
@export var stage_class_entitlements: Array[Dictionary] = []
@export var v3_stage_rewards: Array[Dictionary] = []
@export var portrait_asset_ids: Array[StringName] = []
## Repeatable Mission Control basic-personnel acquisition cost.
@export var basic_recruit_cost: int = 0
