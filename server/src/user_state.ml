open! Core
open! Async
open Memtrace_viewer_common

let percent x = x /. 100.

(* Allocation size (as percentage of total) below which a node is pruned from the trie
   returned to the client. *)
let default_significance_frequency = 0.5 |> percent

(* Upper bound on measurement errors (used in the substring heavy hitters algorithm). *)
let default_tolerance = 0.01 |> percent

(* Number of points in the time series produced for the graph. *)
let graph_size = 450

module Initial = struct
  type t =
    { trace : Raw_trace.t
    ; loc_cache : Location.Cache.t
    ; graph : Data.Graph.t
    ; trie : Data.Fragment_trie.t
    ; peak_allocations : Byte_units.t
    ; peak_allocations_time : Time_ns.Span.t
    ; call_sites : Data.Call_sites.t
    }

  let of_trace trace =
    let loc_cache = Location.Cache.create ~trace () in
    let trace = Raw_trace.of_memtrace_trace trace in
    let filtered_trace = Filtered_trace.create ~trace ~loc_cache ~filter:Filter.default in
    let graph = Graph.build ~trace:filtered_trace ~size:graph_size in
    let trie, call_sites =
      Location_trie.build
        ~trace:filtered_trace
        ~loc_cache
        ~tolerance:default_tolerance
        ~significance_frequency:default_significance_frequency
    in
    let Peak.{ allocations = peak_allocations; time = peak_allocations_time } =
      (* Note that we're computing this now, without a filter applied. This implies that
         "live at peak" means live at the time of peak memory usage, not the time at which
         the filtered allocations are at their maximum. This is both easier to deal with
         and probably more useful. *)
      Peak.find_peak_allocations trace
    in
    { trace; loc_cache; graph; trie; peak_allocations; peak_allocations_time; call_sites }
  ;;
end

type t =
  { mutable data : Data.t
  ; mutable filter : Filter.t
  }
[@@deriving fields ~getters]

let compute
  ~initial_state:
    Initial.
      { trace
      ; loc_cache
      ; trie
      ; peak_allocations
      ; peak_allocations_time
      ; call_sites
      ; graph
      }
  ~filter
  =
  let total_allocations_unfiltered = Data.Fragment_trie.total_allocations trie in
  let trie, call_sites, filtered_graph =
    if Filter.is_default filter
    then trie, call_sites, None
    else (
      let filtered_trace = Filtered_trace.create ~trace ~loc_cache ~filter in
      let trie, call_sites =
        Location_trie.build
          ~trace:filtered_trace
          ~loc_cache
          ~tolerance:default_tolerance
          ~significance_frequency:default_significance_frequency
      in
      let filtered_graph = Graph.build ~trace:filtered_trace ~size:graph_size in
      trie, call_sites, Some filtered_graph)
  in
  let hot_paths = Hot_paths.hot_paths trie in
  let hot_locations = Hot_call_sites.hot_locations trie in
  let info = Some (Raw_trace.info trace) in
  { Data.graph
  ; filtered_graph
  ; trie
  ; peak_allocations
  ; peak_allocations_time
  ; total_allocations_unfiltered
  ; call_sites
  ; hot_paths
  ; hot_locations
  ; info
  }
;;

let create ~initial_state ~filter =
  let data = compute ~initial_state ~filter in
  { data; filter }
;;

let reset initial_state t =
  let filter = Filter.default in
  t.filter <- filter;
  let data = compute ~initial_state ~filter in
  t.filter <- filter;
  t.data <- data
;;

let update initial_state t action =
  match action with
  | Action.Set_filter filter ->
    t.filter <- filter;
    let data = compute ~initial_state ~filter in
    t.data <- data
;;
