(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2016     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* Modified by Lionel Elie Mamane <lionel@mamane.lu> on 9 & 10 Mar 2004:
 *  - handling of absolute filenames (function coq_module)
 *  - coq_module: chop ./// (arbitrary amount of slashes), not only "./"
 *  - function chop_prefix not useful anymore. Deleted.
 *  - correct typo in usage message: "-R" -> "--R"
 *  - shorten the definition of make_path
 * This notice is made to comply with section 2.a of the GPLv2.
 * It may be removed or abbreviated as far as I am concerned.
 *)

open Cdglobals
open Printf

type target_language = HTML | JsCoq | Debug
let target_language : target_language ref = ref JsCoq

(*s \textbf{Usage.} Printed on error output. *)

let usage () =
  prerr_endline "";
  prerr_endline "Usage: udoc <options and files>";
  prerr_endline "  --html               produce a HTML document (default)";
  prerr_endline "  --backend=jscoq      produce a jscoq document";
  prerr_endline "  --backend=debug      produce a debug document";
  prerr_endline "  --stdout             write output to stdout";
  prerr_endline "  -o <file>            write output in file <file>";
  prerr_endline "  -d <dir>             output files into directory <dir>";
  prerr_endline "  -s                   (short) no titles for files";
  prerr_endline "  -l                   light mode (only defs and statements)";
  prerr_endline "  -t <string>          give a title to the document";
  prerr_endline "  --body-only          suppress LaTeX/HTML header and trailer";
  prerr_endline "  --with-header <file> prepend <file> as html reader";
  prerr_endline "  --with-footer <file> append <file> as html footer";
  prerr_endline "  --no-index           do not output the index";
  prerr_endline "  --multi-index        index split in multiple files";
  prerr_endline "  --index <string>     set index name (default is index)";
  prerr_endline "  --toc                output a table of contents";
  prerr_endline "  --no-glob            don't use any globalization information (no links will be inserted at identifiers)";
  prerr_endline "  --quiet              quiet mode (default)";
  prerr_endline "  --verbose            verbose mode";
  prerr_endline "  --no-externals       no links to Coq standard library";
  prerr_endline "  --external <url> <d> set URL for external library d";
  prerr_endline "  --coqlib <url>       set URL for Coq standard library";
  prerr_endline ("                       (default is " ^ Cdglobals.wwwstdlib ^ ")");
  prerr_endline "  --boot               run in boot mode";
  prerr_endline "  --coqlib_path <dir>  set the path where Coq files are installed";
  prerr_endline "  -R <dir> <coqdir>    map physical dir to Coq dir";
  prerr_endline "  -Q <dir> <coqdir>    map physical dir to Coq dir";
  prerr_endline "  --toc-depth <int>    don't include TOC entries for sections below level <int>";
  prerr_endline "";
  exit 1

(*s \textbf{Banner.} Always printed. Notice that it is printed on error
    output, so that when the output of [coqdoc] is redirected this header
    is not (unless both standard and error outputs are redirected, of
    course). *)

let banner () =
  eprintf "This is udoc version %s, compiled on %s\n"
    Cdglobals.version Cdglobals.compile_date;
  flush stderr

let target_full_name f =
  match !target_language with
    | HTML  -> f ^ ".html"
    | JsCoq -> f ^ ".html"
    | Debug -> f ^ ".txt"

(*s \textbf{Separation of files.} Files given on the command line are
    separated according to their type, which is determined by their
    suffix.  Coq files have suffixe \verb!.v! or \verb!.g! and \LaTeX\
    files have suffix \verb!.tex!. *)

let check_if_file_exists f =
  if not (Sys.file_exists f) then begin
    eprintf "coqdoc: %s: no such file\n" f;
    exit 1
  end

(* [paths] maps a physical path to a name *)
let paths = ref []

let add_path dir name =
  let p = normalize_path dir in
  paths := (p,name) :: !paths

(* turn A/B/C into A.B.C *)
let rec name_of_path p name dirname suffix =
  if p = dirname then String.concat "." (if name = "" then suffix else (name::suffix))
  else
    let subdir = Filename.dirname dirname in
    if subdir = dirname then raise Not_found
    else name_of_path p name subdir (Filename.basename dirname::suffix)

(** [coq_module filename] Try to guess the coq module name from the
    filename *)
let coq_module (filename : string) : coq_module =
  let bfname = Filename.chop_extension filename in
  let dirname, fname = normalize_filename bfname in
  let rec change_prefix = function
    (* Follow coqc: if in scope of -R, substitute logical name *)
    (* otherwise, keep only base name *)
    | [] -> fname
    | (p, name) :: rem ->
	try name_of_path p name dirname [fname]
	with Not_found -> change_prefix rem
  in
  change_prefix !paths

let what_file f =
  check_if_file_exists f;
  Vernac_file (f, coq_module f)

(*s \textbf{Reading file names from a file.}
 *  File names may be given
 *  in a file instead of being given on the command
 *  line. [(files_from_file f)] returns the list of file names contained
 *  in the file named [f]. These file names must be separated by spaces,
 *  tabulations or newlines.
 *)

(*s \textbf{Parsing of the command line.} *)

let dvi = ref false
let ps  = ref false
let pdf = ref false

let parse () =
  let files = ref [] in
  let add_file f = files := f :: !files in
  let rec parse_rec = function
    | [] -> ()

    | ("-nopreamble" | "--nopreamble" | "--no-preamble"
      |  "-bodyonly"   | "--bodyonly"   | "--body-only") :: rem ->
	opts := { !opts with header_trailer = false } ;
        parse_rec rem
    | ("-with-header" | "--with-header") :: f ::rem ->
        opts := { !opts with header_trailer   = true;
                             header_file_spec = true;
                             header_file      = f;
                }; parse_rec rem
    | ("-with-header" | "--with-header") :: [] ->
	usage ()
    | ("-with-footer" | "--with-footer") :: f ::rem ->
        opts := { !opts with header_trailer   = true;
                             footer_file_spec = true;
                             footer_file      = f;
                }; parse_rec rem
    | ("-with-footer" | "--with-footer") :: [] ->
	usage ()
    | ("-p" | "--preamble") :: [] ->
	usage ()
    | ("-noindex" | "--noindex" | "--no-index") :: rem ->
	opts := { !opts with index = false; }; parse_rec rem
    | ("-multi-index" | "--multi-index") :: rem ->
	opts := { !opts with multi_index = true; }; parse_rec rem
    | ("-index" | "--index") :: s :: rem ->
	opts := { !opts with index_name = s; }; parse_rec rem
    | ("-index" | "--index") :: [] ->
	usage ()
    | ("-toc" | "--toc" | "--table-of-contents") :: rem ->
	opts := { !opts with toc = true; }; parse_rec rem
    | ("-stdout" | "--stdout") :: rem ->
	out_to := StdOut; parse_rec rem
    | ("-o" | "--output") :: f :: rem ->
	out_to := File (Filename.basename f); output_dir := Filename.dirname f; parse_rec rem
    | ("-o" | "--output") :: [] ->
	usage ()
    | ("-d" | "--directory") :: dir :: rem ->
	output_dir := dir; parse_rec rem
    | ("-d" | "--directory") :: [] ->
	usage ()
    | ("-t" | "-title" | "--title") :: s :: rem ->
	opts := { !opts with title = s; }; parse_rec rem
    | ("-t" | "-title" | "--title") :: [] ->
	usage ()
    | ("-html" | "--html") :: rem ->
	target_language := HTML; parse_rec rem
    | ("--backend=jscoq") :: rem ->
	target_language := JsCoq; parse_rec rem
    | ("--backend=debug") :: rem ->
	target_language := Debug; parse_rec rem
    | ("-toc-depth" | "--toc-depth") :: [] ->
      usage ()
    | ("-toc-depth" | "--toc-depth") :: ds :: rem ->
      let d = try int_of_string ds with
                Failure _ ->
                  (eprintf "--toc-depth must be followed by an integer\n";
                   exit 1)
      in
      opts := { !opts with toc_depth = Some d; }; parse_rec rem

    | ("-h" | "-help" | "-?" | "--help") :: rem ->
	banner (); usage ()
    | ("-V" | "-version" | "--version") :: _ ->
	banner (); exit 0

    | "-R" :: path :: log :: rem ->
	add_path path log; parse_rec rem
    | "-R" :: ([] | [_]) ->
	usage ()
    | "-Q" :: path :: log :: rem ->
	add_path path log; parse_rec rem
    | "-Q" :: ([] | [_]) ->
	usage ()
    | ("-glob-from" | "--glob-from") :: f :: rem ->
	glob_source := GlobFile f; parse_rec rem
    | ("-glob-from" | "--glob-from") :: [] ->
	usage ()
    | ("-no-glob" | "--no-glob") :: rem ->
	glob_source := NoGlob; parse_rec rem
    | ("--external" | "-external") :: u :: logicalpath :: rem ->
	Index.add_external_library logicalpath u; parse_rec rem
    | ("--coqlib" | "-coqlib") :: u :: rem ->
	Cdglobals.coqlib_url := u; parse_rec rem
    | ("--coqlib" | "-coqlib") :: [] ->
	usage ()
    | ("--udoc_path" | "-coqlib_path") :: d :: rem ->
	Cdglobals.udoc_path := d; parse_rec rem
    | ("--coqlib_path" | "-coqlib_path") :: [] ->
	usage ()
    | f :: rem ->
	add_file (what_file f); parse_rec rem
  in
    parse_rec (List.tl (Array.to_list Sys.argv));
    List.rev !files

(* XXX: Uh *)
let copy src dst =
  let cin = open_in src in
  try
    let cout = open_out dst in
    try
      while true do Pervasives.output_char cout (input_char cin) done
    with End_of_file ->
      close_out cout;
      close_in cin
  with Sys_error e ->
    eprintf "%s\n" e;
    exit 1

(*s Backend Selection *)

let output_factory tl =
  let open Output in
  match tl with
  | HTML      -> (module Out_html.Html   : S)
  | JsCoq     -> (module Out_jscoq.JsCoq : S)
  | Debug     -> (module Out_debug.Debug : S)

(*s Functions for generating output files *)

(** gen_one_file [l] *)
let gen_one_file (module OutB : Output.S) (module Cpretty : Cpretty.S)
                 out (l : file list) =
  let out_module (Vernac_file (f, m)) =
    Cpretty.coq_file f m
  in
  OutB.start_file out
    ~toc:!opts.toc
    ~index:!opts.index
    ~split_index:!opts.multi_index
    ~standalone:!opts.header_trailer;
  List.iter out_module l;
  OutB.end_file ()

let gen_mult_files (module OutB : Output.S) (module Cpretty : Cpretty.S)
                   (l : file list) =

  (* XXX: subtitle functionality has been removed. *)
  let out_module (Vernac_file (f, m)) =
    let hf  = target_full_name m                                         in
    with_outfile hf (fun out ->
        (* Disable index and TOC for each file *)
        OutB.start_file out
          ~toc:false
          ~index:false
          ~split_index:false
          ~standalone:!opts.header_trailer;
        Cpretty.coq_file f m;
        OutB.end_file ()
      )
  in
    List.iter out_module l;
    OutB.appendix
      ~toc:!opts.toc
      ~index:!opts.index
      ~split_index:!opts.multi_index
      ~standalone:!opts.header_trailer

let read_glob_file vfile f =
  try Index.read_glob vfile f
  with Sys_error s -> eprintf "Warning: %s (links will not be available)\n" s

let read_glob_file_of = function
  | Vernac_file (f,_) ->
      read_glob_file (Some f) (Filename.chop_extension f ^ ".glob")

let index_module = function
  | Vernac_file (f,m) ->
      Index.add_module m

(** [copy_style_file files] Copy support files to output. *)
let copy_style_files (files : string list) : unit =
  let copy_file file =
    let src = List.fold_left
              Filename.concat !Cdglobals.udoc_path ["html"; file] in
    let dst = coqdoc_out file                                                  in
    if Sys.file_exists src then copy src dst
    else eprintf "Warning: file %s does not exist\n" src
  in List.iter copy_file files

(** [produce_document l] produces a document from list of files [l] *)
let produce_document (l : file list) =

  let module OutB    = (val output_factory !target_language) in
  let module Cpretty = Cpretty.Make(OutB)                    in

  copy_style_files OutB.support_files;

  (* Preload index. *)
  begin match !Cdglobals.glob_source with
    | NoGlob     -> ()
    | DotGlob    -> List.iter read_glob_file_of l
    | GlobFile f -> read_glob_file None f
  end;
  List.iter index_module l;

  match !out_to with
    | StdOut ->
      gen_one_file (module OutB) (module Cpretty) (Format.formatter_of_out_channel stdout) l
    | File f ->
      with_outfile f (fun fmt ->
          gen_one_file (module OutB) (module Cpretty) fmt l
        )
    | MultFiles ->
      gen_mult_files (module OutB) (module Cpretty) l

let produce_output fl = produce_document fl

(*s \textbf{Main program.} Print the banner, parse the command line,
    read the files and then call [produce_document] from module [Web]. *)

let _ =
  let files = parse () in
    Index.init_coqlib_library ();
    if files <> [] then produce_output files
