/-
Copyright (c) 2019 Robert Y. Lewis. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Robert Y. Lewis
-/

import tactic.core system.io data.string.defs
import all

/-!
Used to generate a json file for html docs.

The json file is a list of maps, where each map has the structure
{ name: string,
  type: string,
  doc_string: string,
  filename: string,
  line: int,
  attributes: list string,
  kind: string }

Include this file somewhere in mathlib, e.g. in the `scripts` directory. Make sure mathlib is
precompiled, with `all.lean` generated by `mk_all.sh`.

Usage: `lean --run export_json.lean` creates `json_export.txt` in the current directory.
-/

open tactic io io.fs

/-- The information collected from each declaration -/
structure decl_info :=
(name : name)
(type : string)
(doc_string : option string)
(filename : string)
(line : ℕ)
(attributes : list string) -- not all attributes, we have a hardcoded list to check
(kind : string) -- def, thm, cnst, ax

meta def escape_quotes (s : string) : string :=
s.fold "" (λ s x, s ++ if x = '"' then '\\'.to_string ++ '"'.to_string else x.to_string)

meta def decl_info.to_format : decl_info → format
| ⟨name, type, doc_string, filename, line, attributes, kind⟩ :=
let doc_string := doc_string.get_or_else "",
    attributes := attributes.map repr in
"{" ++ format!"\"name\":\"{to_string name}\", \"type\":{repr type}, \"doc_string\":{repr doc_string}, "
    ++ format!"\"filename\":\"{filename}\",\"line\":{line}, \"attributes\":{attributes}, \"kind\":{repr kind}" ++ "}"

/-- The attributes we check for -/
meta def attribute_list := [`simp, `squash_cast, `move_cast, `elim_cast, `nolint, `ext, `instance]

meta def attributes_of (n : name) : tactic (list string) :=
list.map to_string <$> attribute_list.mfilter (λ attr, succeeds $ has_attribute attr n)

meta def declaration.kind : declaration → string
| (declaration.defn a a_1 a_2 a_3 a_4 a_5) := "def"
| (declaration.thm a a_1 a_2 a_3) := "thm"
| (declaration.cnst a a_1 a_2 a_3) := "cnst"
| (declaration.ax a a_1 a_2) := "ax"

/-- extracts `decl_info` from `d`. Should return `none` instead of failing. -/
meta def process_decl (d : declaration) : tactic (option decl_info) :=
do ff ← d.in_current_file | return none,
   e ← get_env,
   let decl_name := d.to_name,
   if decl_name.is_internal ∨ d.is_auto_generated e then return none else do
   some filename ← return (e.decl_olean decl_name) | return none,
   some ⟨line, _⟩ ← return (e.decl_pos decl_name) | return none,
   doc_string ← (some <$> doc_string decl_name) <|> return none,
   type ← escape_quotes <$> to_string <$> pp d.type,
   attributes ← attributes_of decl_name,
   return $ some ⟨decl_name, type, doc_string, filename, line, attributes, d.kind⟩

meta def run_on_dcl_list (e : environment) (ens : list name) (handle : handle) (is_first : bool) : io unit :=
ens.mfoldl  (λ is_first d_name, do
     d ← run_tactic (e.get d_name),
     odi ← run_tactic (process_decl d),
     match odi with
     | some di := do
        when (bnot is_first) (put_str_ln handle ","),
        put_str_ln handle $ to_string di.to_format,
        return ff
     | none := return is_first
     end) is_first >> return ()

meta def itersplit {α} : list α → ℕ → list (list α)
| l 0 := [l]
| l 1 := let (l1, l2) := l.split in [l1, l2]
| l (k+2) := let (l1, l2) := l.split in itersplit l1 (k+1) ++ itersplit l2 (k+1)

/-- Using `environment.mfold` is much cleaner. Unfortunately this led to a segfault, I think because
of a stack overflow. Converting the environment to a list of declarations and folding over that led
to "deep recursion detected". Instead, we split that list into 8 smaller lists and process them
one by one. More investigation is needed. -/
meta def export_json (filename : string) : io unit :=
do handle ← mk_file_handle filename mode.write,
   put_str_ln handle "[",
   e ← run_tactic get_env,
   let ens := environment.get_decl_names e,
   let enss := itersplit ens 3,
   enss.mfoldl (λ is_first l, do run_on_dcl_list e l handle is_first, return ff) tt,
   put_str_ln handle "]",
   close handle

meta def main : io unit :=
export_json "json_export.txt"
