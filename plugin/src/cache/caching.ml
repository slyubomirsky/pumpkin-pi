open Constr
open Names
open Recordops
open Libnames
open Globnames
open Utilities
open Libobject
open Lib
open Mod_subst
open Defutils
open Reducers
open Environ
open Declarations
open Names

(* --- Database of liftings for higher lifting --- *)

(*
 * This is a persistent cache for liftings
 *)

(* The persistent storage is backed by a normal hashtable *)
module LiftingsCache =
  Hashtbl.Make
    (struct
      type t = (global_reference * global_reference * global_reference)
      let equal =
        (fun (o, n, t) (o', n', t') ->
          eq_gr o o' && eq_gr n n' && eq_gr t t')
      let hash =
        (fun (o, n, t) ->
          Hashset.Combine.combine
            (Hashset.Combine.combine
               (ExtRefOrdered.hash (TrueGlobal o))
               (ExtRefOrdered.hash (TrueGlobal n)))
            (ExtRefOrdered.hash (TrueGlobal t)))
    end)

(* Initialize the lifting cache *)
let lift_cache = LiftingsCache.create 100
             
(*
 * Wrapping the table for persistence
 *)
type lift_obj =
  (global_reference * global_reference * global_reference) *
  (global_reference option)

let cache_lifting (_, (orns_and_trm, lifted_trm)) =
  LiftingsCache.add lift_cache orns_and_trm lifted_trm

let sub_lifting (subst, ((orn_o, orn_n, trm), lifted_trm)) =
  let orn_o, orn_n = map_tuple (subst_global_reference subst) (orn_o, orn_n) in
  let trm = subst_global_reference subst trm in
  let lifted_trm =
    if Option.has_some lifted_trm then
      Some (subst_global_reference subst (Option.get lifted_trm))
    else
      None
  in (orn_o, orn_n, trm), lifted_trm

let inLifts : lift_obj -> obj =
  declare_object { (default_object "LIFTINGS") with
    cache_function = cache_lifting;
    load_function = (fun _ -> cache_lifting);
    open_function = (fun _ -> cache_lifting);
    classify_function = (fun orn_obj -> Substitute orn_obj);
    subst_function = sub_lifting }
              
(*
 * Check if there is a lifting along an ornament for a given term
 *)
let has_lifting_opt (orn_o, orn_n, trm) =
  try
    let orn_o, orn_n = map_tuple global_of_constr (orn_o, orn_n) in
    let trm = global_of_constr trm in
    LiftingsCache.mem lift_cache (orn_o, orn_n, trm)
  with _ ->
    false

(*
 * Lookup a lifting
 *)
let lookup_lifting (orn_o, orn_n, trm) =
  if not (has_lifting_opt (orn_o, orn_n, trm)) then
    None
  else
    let orn_o, orn_n = map_tuple global_of_constr (orn_o, orn_n) in
    let trm = global_of_constr trm in
    let lifted_trm = LiftingsCache.find lift_cache (orn_o, orn_n, trm) in
    try
      Some (Universes.constr_of_global (Option.get lifted_trm))
    with _ ->
      None

(*
 * Add a lifting to the lifting cache
 *)
let save_lifting (orn_o, orn_n, trm) lifted_trm =
  try
    let orn_o, orn_n = map_tuple global_of_constr (orn_o, orn_n) in
    let trm = global_of_constr trm in
    let lifted_trm = global_of_constr lifted_trm in
    let lift_obj = inLifts ((orn_o, orn_n, trm), Some lifted_trm) in
    add_anonymous_leaf lift_obj
  with _ ->
    Feedback.msg_warning (Pp.str "Failed to cache lifting")

(* --- Opaque liftings --- *)

(* Initialize the opaque lifting cache *)
let opaque_lift_cache = LiftingsCache.create 100

(*
 * Wrapping the table for persistence
 *)
type opaque_lift_obj =
  (global_reference * global_reference * global_reference) * bool

let cache_opaque_lifting (_, (orns_and_trm, is_opaque)) =
  LiftingsCache.add opaque_lift_cache orns_and_trm is_opaque

let sub_opaque_lifting (subst, ((orn_o, orn_n, trm), is_opaque)) =
  let orn_o, orn_n = map_tuple (subst_global_reference subst) (orn_o, orn_n) in
  let trm = subst_global_reference subst trm in
  (orn_o, orn_n, trm), is_opaque

let inOpaqueLifts : opaque_lift_obj -> obj =
  declare_object { (default_object "OPAQUE_LIFTINGS") with
    cache_function = cache_opaque_lifting;
    load_function = (fun _ -> cache_opaque_lifting);
    open_function = (fun _ -> cache_opaque_lifting);
    classify_function = (fun opaque_obj -> Substitute opaque_obj);
    subst_function = sub_opaque_lifting }
              
(*
 * Check if there is an opaque lifting along an ornament for a given term
 *)
let has_opaque_lifting_bool (orn_o, orn_n, trm) =
  try
    let orn_o, orn_n = map_tuple global_of_constr (orn_o, orn_n) in
    let trm = global_of_constr trm in
    LiftingsCache.mem opaque_lift_cache (orn_o, orn_n, trm)
  with _ ->
    false

(*
 * Lookup an opaque lifting
 *)
let lookup_opaque (orn_o, orn_n, trm) =
  if has_opaque_lifting_bool (orn_o, orn_n, trm) then
    let orn_o, orn_n = map_tuple global_of_constr (orn_o, orn_n) in
    let trm = global_of_constr trm in
    LiftingsCache.find opaque_lift_cache (orn_o, orn_n, trm)
  else
    false

(*
 * Add an opaque lifting to the opaque lifting cache
 *)
let save_opaque (orn_o, orn_n, trm) =
  try
    let orn_o, orn_n = map_tuple global_of_constr (orn_o, orn_n) in
    let trm = global_of_constr trm in
    let opaque_lift_obj = inOpaqueLifts ((orn_o, orn_n, trm), true) in
    let lift_obj = inLifts ((orn_o, orn_n, trm), Some trm) in
    add_anonymous_leaf opaque_lift_obj;
    add_anonymous_leaf lift_obj
  with _ ->
    Feedback.msg_warning (Pp.str "Failed to cache opaque lifting")

(*
 * Remove an opaque lifting from the opaque lifting cache
 *)
let remove_opaque (orn_o, orn_n, trm) =
  try
    let orn_o, orn_n = map_tuple global_of_constr (orn_o, orn_n) in
    let trm = global_of_constr trm in
    let opaque_lift_obj = inOpaqueLifts ((orn_o, orn_n, trm), false) in
    let lift_obj = inLifts ((orn_o, orn_n, trm), None) in
    add_anonymous_leaf opaque_lift_obj;
    add_anonymous_leaf lift_obj
  with _ ->
    Feedback.msg_warning (Pp.str "Failed to cache opaque lifting")
                         
(* --- Temporary cache of constants --- *)

(*
 * This cache handles any constants encountered while lifting an object.
 * It is purposely not persistent, and only lasts for a single lifting session.
 * Otherwise, we would clog the cache with many constants.
 *)

type temporary_cache = (global_reference, types) Hashtbl.t

(*
 * Initialize the local cache
 *)
let initialize_local_cache () =
  Hashtbl.create 100

(*
 * Check whether a constant is in the local cache
 *)
let is_locally_cached c trm =
  try
    let gr = global_of_constr trm in
    Hashtbl.mem c gr
  with _ ->
    false

(*
 * Lookup a value in the local cache
 *)
let lookup_local_cache c trm =
  try
    let gr = global_of_constr trm in
    Hashtbl.find c gr
  with _ ->
    failwith "not cached"

(*
 * Add a value to the local cache
 *)
let cache_local c trm lifted =
  try
    let gr = global_of_constr trm in
    Hashtbl.add c gr lifted
  with _ ->
    Feedback.msg_warning (Pp.str "can't cache term")
                         
(* --- Ornaments cache --- *)

(*
 * This is a persistent cache for ornaments
 *)
  
(* The persistent storage is backed by a normal hashtable *)
module OrnamentsCache =
  Hashtbl.Make
    (struct
      type t = (global_reference * global_reference)
      let equal =
        (fun (o, n) (o', n') ->
          eq_gr o o' && eq_gr n n')
      let hash =
        (fun (o, n) ->
          Hashset.Combine.combine
            (ExtRefOrdered.hash (TrueGlobal o))
            (ExtRefOrdered.hash (TrueGlobal n)))
    end)

(* Initialize the ornament cache *)
let orn_cache = OrnamentsCache.create 100

(* Initialize the private cache of indexers for algebraic ornamnets *)
let indexer_cache = OrnamentsCache.create 100
                                      
(*
 * The kind of ornament that is stored
 * TODO move this out since also used in lifting
 *)
type kind_of_orn = Algebraic of constr * int | CurryRecord

(*
 * The kind of ornament is saved as an int, so this interprets it
 *)
let int_to_kind (i : int) (indexer_and_off : (constr * int) option) =
  if i = 0 && Option.has_some indexer_and_off then
    let indexer, off = Option.get indexer_and_off in
    Algebraic (indexer, off)
  else if i = 1 then
    CurryRecord
  else
    failwith "Unsupported kind of ornament passed to interpret_kind in caching"

let kind_to_int (k : kind_of_orn) =
  match k with
  | Algebraic _ ->
     0
  | CurryRecord ->
     1
             
(*
 * Wrapping the table for persistence
 *)
type orn_obj =
  (global_reference * global_reference) * (global_reference * global_reference * int)

type indexer_obj =
  (global_reference * global_reference) * (global_reference * int)

let cache_ornament (_, (typs, orns_and_kind)) =
  OrnamentsCache.add orn_cache typs orns_and_kind

let cache_indexer (_, (typs, indexer_and_off)) =
  OrnamentsCache.add indexer_cache typs indexer_and_off

let sub_ornament (subst, (typs, (orn_o, orn_n, kind))) =
  let typs = map_tuple (subst_global_reference subst) typs in
  let orn_o, orn_n = map_tuple (subst_global_reference subst) (orn_o, orn_n) in
  typs, (orn_o, orn_n, kind)

let sub_indexer (subst, (typs, (indexer, off))) =
  let typs = map_tuple (subst_global_reference subst) typs in
  let indexer = subst_global_reference subst indexer in
  typs, (indexer, off)

let inOrns : orn_obj -> obj =
  declare_object { (default_object "ORNAMENTS") with
    cache_function = cache_ornament;
    load_function = (fun _ -> cache_ornament);
    open_function = (fun _ -> cache_ornament);
    classify_function = (fun orn_obj -> Substitute orn_obj);
    subst_function = sub_ornament }

let inIndexers : indexer_obj -> obj =
  declare_object { (default_object "INDEXERS") with
    cache_function = cache_indexer;
    load_function = (fun _ -> cache_indexer);
    open_function = (fun _ -> cache_indexer);
    classify_function = (fun ind_obj -> Substitute ind_obj);
    subst_function = sub_indexer }
                 
(*
 * Precise version
 *)
let has_ornament_exact typs =
  try
    let globals = map_tuple global_of_constr typs in
    OrnamentsCache.mem orn_cache globals
  with _ ->
    false
              
(*
 * Check if an ornament is cached
 *)
let has_ornament typs =
  if has_ornament_exact typs then
    true
  else
    has_ornament_exact (reverse typs)

(*
 * Lookup an ornament
 *)
let lookup_ornament typs =
  let typs = if has_ornament_exact typs then typs else reverse typs in
  if not (has_ornament typs) then
    None
  else
    let globals = map_tuple global_of_constr typs in
    let (orn, orn_inv, i) = OrnamentsCache.find orn_cache globals in
    try
      let orn, orn_inv = map_tuple Universes.constr_of_global (orn, orn_inv) in
      if i = 0 then
        let (indexer, off) = OrnamentsCache.find indexer_cache globals in
        let indexer = Universes.constr_of_global indexer in 
        Some (orn, orn_inv, int_to_kind i (Some (indexer, off)))
      else
        Some (orn, orn_inv, int_to_kind i None)
    with _ ->
      None
(*
 * Add an ornament to the ornament cache
 *)
let save_ornament typs (orn, orn_inv, kind) =
  try
    let globals = map_tuple global_of_constr typs in
    let orn, orn_inv = map_tuple global_of_constr (orn, orn_inv) in
    let orn_obj = inOrns (globals, (orn, orn_inv, kind_to_int kind)) in
    add_anonymous_leaf orn_obj;
    match kind with
    | Algebraic (indexer, off) ->
       let indexer = global_of_constr indexer in
       let ind_obj = inIndexers (globals, (indexer, off)) in
       add_anonymous_leaf ind_obj
    | CurryRecord ->
       ()
  with _ ->
    Feedback.msg_warning (Pp.str "Failed to cache ornament")
 

