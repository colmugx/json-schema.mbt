///|
priv enum ValueType {
  NullType
  BooleanType
  NumberType
  IntegerType
  StringType
  ArrayType
  ObjectType
}

///|
/// `Located` wraps every compiled schema node with the index of the schema
/// resource it belongs to. The arena (`Program.nodes`) stores `Located`
/// nodes, so evaluation can always recover the resource identity — and from
/// it the source document URI — of the plan it is standing in. Nested plans
/// (branches, property schemas, ref targets) are `Located` too.
priv enum Plan {
  Pending
  Accept
  Reject(String)
  Rules(Array[Rule])
  Located(Int32, Plan)
}

///|
priv enum Rule {
  Types(Array[ValueType], String)
  Constant(Json, String)
  Enumeration(Array[Json], String)
  Lower(ExactNumber, Bool, String)
  Upper(ExactNumber, Bool, String)
  Multiple(ExactNumber, String)
  StringLength(Int32?, Int32?, String)
  Pattern(PatternSupport, String)
  Objects(ObjectPlan)
  Arrays(ArrayPlan)
  All(Array[Plan], String)
  Any(Array[Plan], String)
  One(Array[Plan], String)
  Negate(Plan, String)
  Conditional(Plan, Plan?, Plan?)
  Ref(Int32)
  /// `$dynamicRef`: the arena slot is the initially resolved target; the name
  /// is present only when that target actually carries a `$dynamicAnchor`
  /// (otherwise the reference behaves exactly like `Ref`).
  DynamicRef(Int32, String?)
  /// Compiled last within a node so the evaluator can run them as a final
  /// pass over the annotations collected by every earlier keyword.
  UnevaluatedProperties(Plan, String)
  UnevaluatedItems(Plan, String)
}

///|
priv struct ObjectPlan {
  path : String
  properties : Map[String, Plan]
  patterns : Array[(PatternSupport, Plan)]
  additional : Plan?
  required : Array[String]
  names : Plan?
  minimum : Int32?
  maximum : Int32?
  dependent_required : Array[(String, Array[String])]
  dependent_schemas : Array[(String, Plan)]
}

///|
priv struct ArrayPlan {
  path : String
  prefix : Array[Plan]
  items : Plan?
  contains : Plan?
  min_contains : Int32
  max_contains : Int32?
  minimum : Int32?
  maximum : Int32?
  unique : Bool
}

///|
/// Metadata for one schema resource (a `$id`-identified subtree or a whole
/// source document). `uri` is the resource identity: the canonical URI the
/// resource calls itself (`None` only for an anonymous root document).
/// `document_uri` identifies the source document the resource was supplied
/// in, so a schema pointer (which is relative to that document) can be made
/// absolute by appending it to `document_uri`. `dynamic_anchors` maps
/// `$dynamicAnchor` names to arena slots for `$dynamicRef` bookending.
priv struct ResourceMeta {
  uri : String?
  document_uri : String?
  dynamic_anchors : Map[String, Int32]
  dialect : Dialect
}

///|
/// An owned indexed node graph: `$ref` rules jump to arena slots instead of
/// inlining targets, so recursive schemas compile once and validation never
/// builds cyclic heap references or expands plans exponentially. `resources`
/// describes every schema resource the plan spans; `collect_evaluated` is
/// true when a compiled node uses `unevaluatedProperties`/`unevaluatedItems`
/// and the evaluator must track evaluated-instance annotations.
priv struct Program {
  nodes : Array[Plan]
  resources : Array[ResourceMeta]
  collect_evaluated : Bool
}

///|
/// An owned, precompiled 2020-12 validation plan. Compilation does not mutate
/// the source document; constants and enumerations are copied into the plan.
/// After compilation the schema depends only on the plan: later mutations to
/// the documents or the registry map are not observed.
pub struct Schema {
  priv plan : Program
}

///|
fn pointer_step(path : String, key : String) -> String {
  path + "/" + key.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn owned_json(value : Json) -> Json {
  match value {
    Object(members) => {
      let copy : Map[String, Json] = Map([])
      for key, child in members {
        copy.set(key, owned_json(child))
      }
      Json::object(copy)
    }
    Array(values) => Json::array(values.map(owned_json))
    _ => value
  }
}
