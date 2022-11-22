(lang dune 2.9)
(name dkml-apps)
(version 1.0.2~prerel13)

(generate_opam_files true)

(source
 (github diskuv/dkml-runtime-apps))
(license Apache-2.0)
(authors "Diskuv, Inc. <opensource+diskuv-ocaml@support.diskuv.com>")
(maintainers "opensource+diskuv-ocaml@support.diskuv.com")
(homepage "https://diskuv.gitlab.io/diskuv-ocaml")
(bug_reports "https://github.com/diskuv/dkml-runtime-apps/issues")

(package
 (name dkml-runtimelib)
 (synopsis "Runtime library used by CLI applications and Opam plugins in a Diskuv OCaml installation")
 (depends
  (ocaml        (>= 4.12.1))
  (bos          (>= 0.2.0))
  (sexplib      (>= 0.14.0))
  (dkml-c-probe (>= 3.0.0))))

(package
 (name dkml-runtimescripts)
 (synopsis "Runtime scripts used by CLI applications and Opam plugins in a Diskuv OCaml installation")
 (depends
  (ocaml        (>= 4.12.1))
  (bos          (>= 0.2.0))
  (fpath        (>= 0.7.0))
  (rresult      (>= 0.7.0))
  dkml-compiler-env
  (dkml-runtime-common        (>= 1.0.2~prerel7))
  (dkml-runtime-distribution  (>= 1.0.2~prerel7))
  (crunch       (>= 3.2.0))))

(package
 (name with-dkml)
 (synopsis "Gives Windows access to Opam and MSYS2 environments")
 (depends
  (ocaml            (>= 4.12.1))
  (dkml-runtimelib  (= :version))
  (dkml-runtime-common (>= 1.0.2~prerel7))
  (logs             (>= 0.7.0))
  (fmt              (>= 0.8.9))
  (sha              (>= 1.15.2))
  (crunch           (>= 3.2.0))))

(package
 (name dkml-apps)
 (synopsis "CLI applications available in Diskuv OCaml installations")
 (description "'dkml-fswatch' is a Windows port of fswatch suitable for 'dune --watch'.")
 (depends
  (ocaml (>= 4.12.1))))

(package
 (name opam-dkml)
 (synopsis "Opam plugin for Diskuv OCaml (DKML)")
 (description "An opam plugin where 'opam dkml init' creates a local Windows-friendly Opam switch configured with DKML Opam repositories and options")
 (depends
  (ocaml                (>= 4.12.1))
  (dkml-runtimelib      (= :version))
  (dkml-runtimescripts  (= :version))
  (logs                 (>= 0.7.0))
  (fmt                  (>= 0.8.9))
  (cmdliner             (>= 1.0))))
