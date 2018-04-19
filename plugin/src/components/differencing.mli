(*
 * Differencing for ornamenting inductive types
 *)

open Term
open Environ
open Evd
open Names
open Lifting
       
(* --- Ornamental differencing --- *)


(* 
 * Search two inductive types for an ornamental promotion between them
 *)
val search_orn_inductive :
  env ->
  evar_map ->
  Id.t -> (* name to assign an indexer function, if one is found *)
  types -> (* old inductive type *)
  types -> (* new inductive type *)
  promotion (* ornamental prmotion *)
