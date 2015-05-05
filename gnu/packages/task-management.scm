;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2015 Tomáš Čech <sleep_walker@suse.cz>
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

(define-module (gnu packages task-management)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (gnu packages gnutls)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages lua)
  #:use-module (guix download)
  #:use-module (guix build-system cmake))

(define-public taskwarrior
  (package
    (name "taskwarrior")
    (version "2.4.3")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "http://taskwarrior.org/download/task-" version ".tar.gz"))
       (sha256 (base32
                "1lkbw2fhshynbl7hppar1viapyrs712s14xhd8p3l8gyhvxbh0mv"))))
    (build-system cmake-build-system)
    (inputs
     `(("gnutls" ,gnutls)
       ("lua" ,lua)
       ("util-linux" ,util-linux)))
    (arguments
     `(#:tests? #f ; No tests implemented.
       #:phases
       (modify-phases %standard-phases
         (add-before
          'patch-source-shebangs 'remove-broken-symlinks
          (lambda _
            ;; These files are broken symlinks - delete them.
            (delete-file "src/cal")
            (delete-file "src/calendar")
            (delete-file "src/tw"))))))
     (home-page "http://taskwarrior.org")
    (synopsis "Command line task manager")
    (description
     "Taskwarrior is a command-line task manager following the Getting Things
Done time management method.  It supports network synchronization, filtering
and querying data, exposing task data in multiple formats to other tools.")
    (license license:expat)))