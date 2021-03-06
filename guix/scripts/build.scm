;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2012, 2013, 2014, 2015 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2013 Mark H Weaver <mhw@netris.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (guix scripts build)
  #:use-module (guix ui)
  #:use-module (guix scripts)
  #:use-module (guix store)
  #:use-module (guix derivations)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (guix monads)
  #:use-module (guix gexp)
  #:autoload   (guix http-client) (http-fetch http-get-error?)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (ice-9 vlist)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-26)
  #:use-module (srfi srfi-34)
  #:use-module (srfi srfi-37)
  #:autoload   (gnu packages) (specification->package %package-module-path)
  #:autoload   (guix download) (download-to-store)
  #:export (%standard-build-options
            set-build-options-from-command-line
            set-build-options-from-command-line*
            show-build-options-help

            guix-build))

(define %default-log-urls
  ;; Default base URLs for build logs.
  '("http://hydra.gnu.org/log"))

;; XXX: The following procedure cannot be in (guix store) because of the
;; dependency on (guix derivations).
(define* (log-url store file #:key (base-urls %default-log-urls))
  "Return a URL under one of the BASE-URLS where a build log for FILE can be
found.  Return #f if no build log was found."
  (define (valid-url? url)
    ;; Probe URL and return #t if it is accessible.
    (guard (c ((http-get-error? c) #f))
      (close-port (http-fetch url #:buffered? #f))
      #t))

  (define (find-url file)
    (let ((base (basename file)))
      (any (lambda (base-url)
             (let ((url (string-append base-url "/" base)))
               (and (valid-url? url) url)))
           base-urls)))

  (cond ((derivation-path? file)
         (catch 'system-error
           (lambda ()
             ;; Usually we'll have more luck with the output file name since
             ;; the deriver that was used by the server could be different, so
             ;; try one of the output file names.
             (let ((drv (call-with-input-file file read-derivation)))
               (or (find-url (derivation->output-path drv))
                   (find-url file))))
           (lambda args
             ;; As a last resort, try the .drv.
             (if (= ENOENT (system-error-errno args))
                 (find-url file)
                 (apply throw args)))))
        (else
         (find-url file))))

(define (register-root store paths root)
  "Register ROOT as an indirect GC root for all of PATHS."
  (let* ((root (string-append (canonicalize-path (dirname root))
                              "/" root)))
    (catch 'system-error
      (lambda ()
        (match paths
          ((path)
           (symlink path root)
           (add-indirect-root store root))
          ((paths ...)
           (fold (lambda (path count)
                   (let ((root (string-append root
                                              "-"
                                              (number->string count))))
                     (symlink path root)
                     (add-indirect-root store root))
                   (+ 1 count))
                 0
                 paths))))
      (lambda args
        (leave (_ "failed to create GC root `~a': ~a~%")
               root (strerror (system-error-errno args)))))))

(define (package-with-source store p uri)
  "Return a package based on P but with its source taken from URI.  Extract
the new package's version number from URI."
  (define (numeric-extension? file-name)
    ;; Return true if FILE-NAME ends with digits.
    (string-every char-set:hex-digit (file-extension file-name)))

  (define (tarball-base-name file-name)
    ;; Return the "base" of FILE-NAME, removing '.tar.gz' or similar
    ;; extensions.
    ;; TODO: Factorize.
    (cond ((not (file-extension file-name))
           file-name)
          ((numeric-extension? file-name)
           file-name)
          ((string=? (file-extension file-name) "tar")
           (file-sans-extension file-name))
          ((file-extension file-name)
           (tarball-base-name (file-sans-extension file-name)))
          (else
           file-name)))

  (let ((base (tarball-base-name (basename uri))))
    (let-values (((name version)
                  (package-name->name+version base)))
      (package (inherit p)
               (version (or version (package-version p)))

               ;; Use #:recursive? #t to allow for directories.
               (source (download-to-store store uri
                                          #:recursive? #t))))))


;;;
;;; Standard command-line build options.
;;;

(define (show-build-options-help)
  "Display on the current output port help about the standard command-line
options handled by 'set-build-options-from-command-line', and listed in
'%standard-build-options'."
  (display (_ "
  -L, --load-path=DIR    prepend DIR to the package module search path"))
  (display (_ "
  -K, --keep-failed      keep build tree of failed builds"))
  (display (_ "
  -n, --dry-run          do not build the derivations"))
  (display (_ "
      --fallback         fall back to building when the substituter fails"))
  (display (_ "
      --no-substitutes   build instead of resorting to pre-built substitutes"))
  (display (_ "
      --substitute-urls=URLS
                         fetch substitute from URLS if they are authorized"))
  (display (_ "
      --no-build-hook    do not attempt to offload builds via the build hook"))
  (display (_ "
      --max-silent-time=SECONDS
                         mark the build as failed after SECONDS of silence"))
  (display (_ "
      --timeout=SECONDS  mark the build as failed after SECONDS of activity"))
  (display (_ "
      --verbosity=LEVEL  use the given verbosity LEVEL"))
  (display (_ "
      --rounds=N         build N times in a row to detect non-determinism"))
  (display (_ "
  -c, --cores=N          allow the use of up to N CPU cores for the build"))
  (display (_ "
  -M, --max-jobs=N       allow at most N build jobs")))

(define (set-build-options-from-command-line store opts)
  "Given OPTS, an alist as returned by 'args-fold' given
'%standard-build-options', set the corresponding build options on STORE."
  ;; TODO: Add more options.
  (set-build-options store
                     #:keep-failed? (assoc-ref opts 'keep-failed?)
                     #:rounds (assoc-ref opts 'rounds)
                     #:build-cores (or (assoc-ref opts 'cores) 0)
                     #:max-build-jobs (or (assoc-ref opts 'max-jobs) 1)
                     #:fallback? (assoc-ref opts 'fallback?)
                     #:use-substitutes? (assoc-ref opts 'substitutes?)
                     #:substitute-urls (assoc-ref opts 'substitute-urls)
                     #:use-build-hook? (assoc-ref opts 'build-hook?)
                     #:max-silent-time (assoc-ref opts 'max-silent-time)
                     #:timeout (assoc-ref opts 'timeout)
                     #:print-build-trace (assoc-ref opts 'print-build-trace?)
                     #:verbosity (assoc-ref opts 'verbosity)))

(define set-build-options-from-command-line*
  (store-lift set-build-options-from-command-line))

(define %standard-build-options
  ;; List of standard command-line options for tools that build something.
  (list (option '(#\L "load-path") #t #f
                (lambda (opt name arg result . rest)
                  ;; XXX: Imperatively modify the search paths.
                  (%package-module-path (cons arg (%package-module-path)))
                  (set! %load-path (cons arg %load-path))
                  (set! %load-compiled-path (cons arg %load-compiled-path))

                  (apply values (cons result rest))))
        (option '(#\K "keep-failed") #f #f
                (lambda (opt name arg result . rest)
                  (apply values
                         (alist-cons 'keep-failed? #t result)
                         rest)))
        (option '("rounds") #t #f
                (lambda (opt name arg result . rest)
                  (apply values
                         (alist-cons 'rounds (string->number* arg)
                                     result)
                         rest)))
        (option '("fallback") #f #f
                (lambda (opt name arg result . rest)
                  (apply values
                         (alist-cons 'fallback? #t
                                     (alist-delete 'fallback? result))
                         rest)))
        (option '("no-substitutes") #f #f
                (lambda (opt name arg result . rest)
                  (apply values
                         (alist-cons 'substitutes? #f
                                     (alist-delete 'substitutes? result))
                         rest)))
        (option '("substitute-urls") #t #f
                (lambda (opt name arg result . rest)
                  (apply values
                         (alist-cons 'substitute-urls
                                     (string-tokenize arg)
                                     (alist-delete 'substitute-urls result))
                         rest)))
        (option '("no-build-hook") #f #f
                (lambda (opt name arg result . rest)
                  (apply values
                         (alist-cons 'build-hook? #f
                                     (alist-delete 'build-hook? result))
                         rest)))
        (option '("max-silent-time") #t #f
                (lambda (opt name arg result . rest)
                  (apply values
                         (alist-cons 'max-silent-time (string->number* arg)
                                     result)
                         rest)))
        (option '("timeout") #t #f
                (lambda (opt name arg result . rest)
                  (apply values
                         (alist-cons 'timeout (string->number* arg) result)
                         rest)))
        (option '("verbosity") #t #f
                (lambda (opt name arg result . rest)
                  (let ((level (string->number arg)))
                    (apply values
                           (alist-cons 'verbosity level
                                       (alist-delete 'verbosity result))
                           rest))))
        (option '(#\c "cores") #t #f
                (lambda (opt name arg result . rest)
                  (let ((c (false-if-exception (string->number arg))))
                    (if c
                        (apply values (alist-cons 'cores c result) rest)
                        (leave (_ "not a number: '~a' option argument: ~a~%")
                               name arg)))))
        (option '(#\M "max-jobs") #t #f
                (lambda (opt name arg result . rest)
                  (let ((c (false-if-exception (string->number arg))))
                    (if c
                        (apply values (alist-cons 'max-jobs c result) rest)
                        (leave (_ "not a number: '~a' option argument: ~a~%")
                               name arg)))))))


;;;
;;; Command-line options.
;;;

(define %default-options
  ;; Alist of default option values.
  `((system . ,(%current-system))
    (build-mode . ,(build-mode normal))
    (graft? . #t)
    (substitutes? . #t)
    (build-hook? . #t)
    (print-build-trace? . #t)
    (max-silent-time . 3600)
    (verbosity . 0)))

(define (show-help)
  (display (_ "Usage: guix build [OPTION]... PACKAGE-OR-DERIVATION...
Build the given PACKAGE-OR-DERIVATION and return their output paths.\n"))
  (display (_ "
  -e, --expression=EXPR  build the package or derivation EXPR evaluates to"))
  (display (_ "
  -f, --file=FILE        build the package or derivation that the code within
                         FILE evaluates to"))
  (display (_ "
  -S, --source           build the packages' source derivations"))
  (display (_ "
      --sources[=TYPE]   build source derivations; TYPE may optionally be one
                         of \"package\", \"all\" (default), or \"transitive\""))
  (display (_ "
  -s, --system=SYSTEM    attempt to build for SYSTEM--e.g., \"i686-linux\""))
  (display (_ "
      --target=TRIPLET   cross-build for TRIPLET--e.g., \"armel-linux-gnu\""))
  (display (_ "
      --with-source=SOURCE
                         use SOURCE when building the corresponding package"))
  (display (_ "
      --no-grafts        do not graft packages"))
  (display (_ "
  -d, --derivations      return the derivation paths of the given packages"))
  (display (_ "
      --check            rebuild items to check for non-determinism issues"))
  (display (_ "
  -r, --root=FILE        make FILE a symlink to the result, and register it
                         as a garbage collector root"))
  (display (_ "
      --log-file         return the log file names for the given derivations"))
  (newline)
  (show-build-options-help)
  (newline)
  (display (_ "
  -h, --help             display this help and exit"))
  (display (_ "
  -V, --version          display version information and exit"))
  (newline)
  (show-bug-report-information))

(define %options
  ;; Specifications of the command-line options.
  (cons* (option '(#\h "help") #f #f
                 (lambda args
                   (show-help)
                   (exit 0)))
         (option '(#\V "version") #f #f
                 (lambda args
                   (show-version-and-exit "guix build")))
         (option '(#\S "source") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'source #t result)))
         (option '("sources") #f #t
                 (lambda (opt name arg result)
                   (match arg
                     ("package"
                      (alist-cons 'source #t result))
                     ((or "all" #f)
                      (alist-cons 'source package-direct-sources result))
                     ("transitive"
                      (alist-cons 'source package-transitive-sources result))
                     (else
                      (leave (_ "invalid argument: '~a' option argument: ~a, ~
must be one of 'package', 'all', or 'transitive'~%")
                             name arg)))))
        (option '("check") #f #f
                (lambda (opt name arg result . rest)
                  (apply values
                         (alist-cons 'build-mode (build-mode check)
                                     result)
                         rest)))
         (option '(#\s "system") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'system arg
                               (alist-delete 'system result eq?))))
         (option '("target") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'target arg
                               (alist-delete 'target result eq?))))
         (option '(#\d "derivations") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'derivations-only? #t result)))
         (option '(#\e "expression") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'expression arg result)))
         (option '(#\f "file") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'file arg result)))
         (option '(#\n "dry-run") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'dry-run? #t result)))
         (option '(#\r "root") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'gc-root arg result)))
         (option '("log-file") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'log-file? #t result)))
         (option '("with-source") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'with-source arg result)))
         (option '("no-grafts") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'graft? #f
                               (alist-delete 'graft? result eq?))))

         %standard-build-options))

(define (options->things-to-build opts)
  "Read the arguments from OPTS and return a list of high-level objects to
build---packages, gexps, derivations, and so on."
  (define (validate-type x)
    (unless (or (package? x) (derivation? x) (gexp? x) (procedure? x))
      (leave (_ "~s: not something we can build~%") x)))

  (define (ensure-list x)
    (let ((lst (match x
                 ((x ...) x)
                 (x       (list x)))))
      (for-each validate-type lst)
      lst))

  (append-map (match-lambda
                (('argument . (? string? spec))
                 (cond ((derivation-path? spec)
                        (list (call-with-input-file spec read-derivation)))
                       ((store-path? spec)
                        ;; Nothing to do; maybe for --log-file.
                        '())
                       (else
                        (list (specification->package spec)))))
                (('file . file)
                 (ensure-list (load* file (make-user-module '()))))
                (('expression . str)
                 (ensure-list (read/eval str)))
                (('argument . (? derivation? drv))
                 drv)
                (_ '()))
              opts))

(define (options->derivations store opts)
  "Given OPTS, the result of 'args-fold', return a list of derivations to
build."
  (define transform
    (options->transformation opts))

  (define package->derivation
    (match (assoc-ref opts 'target)
      (#f package-derivation)
      (triplet
       (cut package-cross-derivation <> <> triplet <>))))

  (define src    (assoc-ref opts 'source))
  (define system (assoc-ref opts 'system))
  (define graft? (assoc-ref opts 'graft?))

  (parameterize ((%graft? graft?))
    (append-map (match-lambda
                  ((? package? p)
                   (match src
                     (#f
                      (list (package->derivation store p system)))
                     (#t
                      (let ((s (package-source p)))
                        (list (package-source-derivation store s))))
                     (proc
                      (map (cut package-source-derivation store <>)
                           (proc p)))))
                  ((? derivation? drv)
                   (list drv))
                  ((? procedure? proc)
                   (list (run-with-store store
                           (mbegin %store-monad
                             (set-guile-for-build (default-guile))
                             (proc))
                           #:system system)))
                  ((? gexp? gexp)
                   (list (run-with-store store
                           (mbegin %store-monad
                             (set-guile-for-build (default-guile))
                             (gexp->derivation "gexp" gexp
                                               #:system system))))))
                (transform store (options->things-to-build opts)))))

(define (transform-package-source sources)
  "Return a transformation procedure that uses replaces package sources with
the matching URIs given in SOURCES."
  (define new-sources
    (map (lambda (uri)
           (cons (package-name->name+version (basename uri))
                 uri))
         sources))

  (lambda (store packages)
    (let loop ((packages packages)
               (sources  new-sources)
               (result   '()))
      (match packages
        (()
         (unless (null? sources)
           (warning (_ "sources do not match any package:~{ ~a~}~%")
                    (match sources
                      (((name . uri) ...)
                       uri))))
         (reverse result))
        (((? package? p) tail ...)
         (let ((source (assoc-ref sources (package-name p))))
           (loop tail
                 (alist-delete (package-name p) sources)
                 (cons (if source
                           (package-with-source store p source)
                           p)
                       result))))
        ((thing tail ...)
         (loop tail sources result))))))

(define %transformations
  ;; Transformations that can be applied to things to build.  The car is the
  ;; key used in the option alist, and the cdr is the transformation
  ;; procedure; it is called with two arguments: the store, and a list of
  ;; things to build.
  `((with-source . ,transform-package-source)))

(define (options->transformation opts)
  "Return a procedure that, when passed a list of things to build (packages,
derivations, etc.), applies the transformations specified by OPTS."
  (apply compose
         (map (match-lambda
                ((key . transform)
                 (let ((args (filter-map (match-lambda
                                           ((k . arg)
                                            (and (eq? k key) arg)))
                                         opts)))
                   (if (null? args)
                       (lambda (store things) things)
                       (transform args)))))
              %transformations)))

(define (show-build-log store file urls)
  "Show the build log for FILE, falling back to remote logs from URLS if
needed."
  (let ((log (or (log-file store file)
                 (log-url store file #:base-urls urls))))
    (if log
        (format #t "~a~%" log)
        (leave (_ "no build log for '~a'~%") file))))


;;;
;;; Entry point.
;;;

(define (guix-build . args)
  (with-error-handling
    ;; Ask for absolute file names so that .drv file names passed from the
    ;; user to 'read-derivation' are absolute when it returns.
    (with-fluids ((%file-port-name-canonicalization 'absolute))
      (let* ((opts  (parse-command-line args %options
                                        (list %default-options)))
             (store (open-connection))
             (mode  (assoc-ref opts 'build-mode))
             (drv   (options->derivations store opts))
             (urls  (map (cut string-append <> "/log")
                         (if (assoc-ref opts 'substitutes?)
                             (or (assoc-ref opts 'substitute-urls)
                                 ;; XXX: This does not necessarily match the
                                 ;; daemon's substitute URLs.
                                 %default-substitute-urls)
                             '())))
             (items (filter-map (match-lambda
                                  (('argument . (? store-path? file))
                                   file)
                                  (_ #f))
                                opts))
             (roots (filter-map (match-lambda
                                  (('gc-root . root) root)
                                  (_ #f))
                                opts)))

        (set-build-options-from-command-line store opts)
        (unless (assoc-ref opts 'log-file?)
          (show-what-to-build store drv
                              #:use-substitutes? (assoc-ref opts 'substitutes?)
                              #:dry-run? (assoc-ref opts 'dry-run?)
                              #:mode mode))

        (cond ((assoc-ref opts 'log-file?)
               (for-each (cut show-build-log store <> urls)
                         (delete-duplicates
                          (append (map derivation-file-name drv)
                                  items))))
              ((assoc-ref opts 'derivations-only?)
               (format #t "~{~a~%~}" (map derivation-file-name drv))
               (for-each (cut register-root store <> <>)
                         (map (compose list derivation-file-name) drv)
                         roots))
              ((not (assoc-ref opts 'dry-run?))
               (and (build-derivations store drv mode)
                    (for-each show-derivation-outputs drv)
                    (for-each (cut register-root store <> <>)
                              (map (lambda (drv)
                                     (map cdr
                                          (derivation->output-paths drv)))
                                   drv)
                              roots))))))))
