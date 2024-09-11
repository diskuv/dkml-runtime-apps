(lang dune 2.9)
(name dkml-apps)
(version 2.1.3)

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
 (synopsis "Runtime library used by CLI applications and Opam plugins in a DkML installation")
 (depends
  (ocaml        (>= 4.12.1))
  (bos          (>= 0.2.1))
  (digestif     (>= 1.1.4))
  (dkml-c-probe (>= 3.0.0))
  (sexplib      (>= 0.14.0))
  (ptime        (>= 1.1.0))
  (uri          (>= 4.4.0))
  (xdg          (>= 3.15.0))))

(package
 (name dkml-runtimescripts)
 (synopsis "Runtime scripts used by CLI applications and Opam plugins in a DkML installation")
 (depends
  (ocaml        (>= 4.12.1))
  (bos          (>= 0.2.1))
  (fpath        (>= 0.7.0))
  (re           (>= 1.10.0))
  (rresult      (>= 0.7.0))
  (dkml-compiler-src          (= :version))
  (dkml-runtime-common        (= :version))
  (dkml-runtime-distribution  (= :version))
  (crunch       (>= 3.3.1))))

(package
 (name with-dkml)
 (synopsis "Gives Windows access to Opam and MSYS2 environments")
 (depends
  (ocaml                (>= 4.12.1))
  (dkml-runtimelib      (= :version))
  (dkml-runtimescripts  (= :version))
  (dkml-runtime-common  (= :version))
  (logs                 (>= 0.7.0))
  (fmt                  (>= 0.8.9))
  (sha                  (>= 1.15.2))
  (crunch               (>= 3.3.1))))

(package
 (name dkml-apps)
 (synopsis "CLI applications available in DkML installations")
 (description "'dkml-fswatch' is a Windows port of fswatch suitable for 'dune --watch'.")
 (depends
  (ocaml              (>= 4.12.1))
  (bos                (>= 0.2.1))
  (dune-configurator  (>= 2.9.3))))

(package
 (name dkml-exe-lib)
 (synopsis "Library containing all the code for the 'dkml' executable")
 (description "'dkml init' creates a local Windows-friendly Opam switch configured with DkML Opam repositories and options")
 (depends
  (ocaml                (>= 4.12.1))
  (dkml-runtimelib      (= :version))
  (dkml-runtimescripts  (= :version))
  (logs                 (>= 0.7.0))
  (fmt                  (>= 0.8.9))
  (cmdliner             (>= 1.1))))

(package
 (name dkml-exe)
 (synopsis "'dkml' executable")
 (description "'dkml init' creates a local Windows-friendly Opam switch configured with DkML Opam repositories and options")
 (depends
  (dkml-exe-lib         (= :version))))

(package
 (name opam-dkml)
 (synopsis "Opam plugin for DkML. Deprecated; use 'dkml' executable instead")
 (description "An opam plugin where 'opam dkml init' creates a local Windows-friendly Opam switch configured with DkML Opam repositories and options")
 (depends
  (dkml-exe-lib         (= :version))))
