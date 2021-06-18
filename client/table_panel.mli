open! Core
open! Async_kernel
open Bonsai_web
open Memtrace_viewer_common

type t =
  { view : Vdom.Node.t
  ; key_handler : Vdom_keyboard.Keyboard_event_handler.t
  ; selection : Data.Fragment.t option
  ; reset_selection : unit -> Ui_event.t
  }

val component
  :  data:Data.t Bonsai.Value.t
  -> orient:Data.Orientation.t Bonsai.Value.t
  -> focus:Data.Fragment.t Bonsai.Value.t
  -> t Bonsai.Computation.t
