(lang dune 2.9)
(name dkml-apps)
(version 0.4.0~prerel69)

(generate_opam_files true)

(source
 (github diskuv/dkml-runtime-apps))
(license Apache-2.0)
(authors "Diskuv, Inc. <opensource+diskuv-ocaml@support.diskuv.com>")
(maintainers "opensource+diskuv-ocaml@support.diskuv.com")
(homepage "https://diskuv.gitlab.io/diskuv-ocaml")
(bug_reports "https://github.com/diskuv/dkml-runtime-apps/issues")

(package
 (name dkml-runtime)
 (synopsis "Runtime scripts used by CLI applications and Opam plugins in a Diskuv OCaml installation")
 (depends
  (ocaml (>= 4.12.1))
  (crunch       (and (>= 3.2.0) :build))
  (astring      (>= 0.8.5))
  (bos          (>= 0.2.0))
  (sexplib      (>= 0.14.0))
  (dkml-c-probe (>= 2.0.0~))))

(package
 (name dkml-apps)
 (synopsis "CLI applications available in Diskuv OCaml installations")
 (description "'with-dkml' gives Windows access to Opam and MSYS2 environments. 'findup' locates an ancestor directory containing a searched-for file. (deprecated; use diskuvbox instead).")
 (depends
  (ocaml (>= 4.12.1))
  (dkml-runtime (= :version))
  (sexplib  (>= 0.14.0))
  (logs     (>= 0.7.0))
  (fmt      (>= 0.8.9))
  (sha      (>= 1.15.2))))

(package
 (name opam-dkml)
 (synopsis "Opam plugin for Diskuv OCaml (DKML)")
 (description "An opam plugin where 'opam dkml init' creates a local Windows-friendly Opam switch configured with DKML Opam repositories and options")
 (depends
  (ocaml (>= 4.12.1))
  (dkml-runtime (= :version))
  (logs     (>= 0.7.0))
  (fmt      (>= 0.8.9))
  (cmdliner (>= 1.0))))
