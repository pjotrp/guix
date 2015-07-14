;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2015 David Thompson <davet@gnu.org>
;;; Copyright © 2015 Pjotr Prins <pjotr.public01@thebird.nl>
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

(define-module (guix build rubygem-build-system)
  #:use-module ((guix build gnu-build-system) #:prefix gnu:)
  #:use-module (guix build utils)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:export (%standard-phases
            rubygem-build))

;; Commentary:
;;
;; Builder-side code of the standard Ruby package build procedure.
;;
;; Code:

(define (first-matching-file pattern)
  "Return the first file name that matches PATTERN in the current working
directory."
  (match (find-files "." pattern)
    ((file-name . _) file-name)
    (() (error "No files matching pattern: " pattern))))

(define* (unpack #:key source #:allow-other-keys)
  "Simple copy of source into the build directory"
  (copy-file source (basename source)))

(define* (check #:key tests? test-target #:allow-other-keys)
  (if tests?
      (zero? (system* "rake" test-target))
      #t))

(define* (install #:key source inputs outputs #:allow-other-keys)
  (let* ((ruby-version
          (match:substring (string-match "ruby-(.*)\\.[0-9]$"
                                         (assoc-ref inputs "ruby"))
                           1))
         (out (assoc-ref outputs "out"))
         (gem-home (string-append out "/lib/ruby/gems/" ruby-version ".0")))
    (setenv "GEM_HOME" gem-home)
    (mkdir-p gem-home)
    (zero? (system* "gem" "install" "--ignore-dependencies" "--local"
                    (first-matching-file "\\.gem$")
                    ;; Executables should go into /bin, not /lib/ruby/gems.
                    "--bindir" (string-append out "/bin")))))

(define %standard-phases
  (modify-phases gnu:%standard-phases
    (delete 'configure)
    (delete 'build)
    (delete 'check)
    ; (add-after 'unpack 'gitify gitify)
    ; (replace 'build build)
    (replace 'unpack unpack)
    (replace 'install install)
    ; (replace 'check check)
    ))

(define* (rubygem-build #:key inputs (phases %standard-phases)
                     #:allow-other-keys #:rest args)
  (apply gnu:gnu-build #:inputs inputs #:phases phases args))
