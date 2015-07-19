;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2014, 2015 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2015 Mark H Weaver <mhw@netris.org>
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

(define-module (gnu system install)
  #:use-module (gnu)
  #:use-module (guix gexp)
  #:use-module (guix store)
  #:use-module (guix monads)
  #:use-module ((guix store) #:select (%store-prefix))
  #:use-module (guix profiles)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages cryptsetup)
  #:use-module (gnu packages package-management)
  #:use-module (gnu packages disk)
  #:use-module (gnu packages grub)
  #:use-module (gnu packages texinfo)
  #:use-module (gnu packages compression)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-26)
  #:export (self-contained-tarball
            installation-os))

;;; Commentary:
;;;
;;; This module provides an 'operating-system' definition for use on images
;;; for USB sticks etc., for the installation of the GNU system.
;;;
;;; Code:


(define* (self-contained-tarball #:key (guix guix))
  "Return a self-contained tarball containing a store initialized with the
closure of GUIX.  The tarball contains /gnu/store, /var/guix, and a profile
under /root/.guix-profile where GUIX is installed."
  (mlet %store-monad ((profile (profile-derivation
                                (manifest
                                 (list (package->manifest-entry guix))))))
    (define build
      #~(begin
          (use-modules (guix build utils)
                       (gnu build install))

          (define %root "root")

          (setenv "PATH"
                  (string-append #$guix "/sbin:" #$tar "/bin:" #$xz "/bin"))

          ;; Note: there is not much to gain here with deduplication and there
          ;; is the overhead of the '.links' directory, so turn it off.
          (populate-single-profile-directory %root
                                             #:profile #$profile
                                             #:closure "profile"
                                             #:deduplicate? #f)

          ;; Create the tarball.  Use GNU format so there's no file name
          ;; length limitation.
          (with-directory-excursion %root
            (zero? (system* "tar" "--xz" "--format=gnu"
                            "--owner=root:0" "--group=root:0"
                            "--mtime=@0"          ;for files in /var/guix
                            "--check-links"
                            "-cvf" #$output
                            ;; Avoid adding / and /var to the tarball,
                            ;; so that the ownership and permissions of those
                            ;; directories will not be overwritten when
                            ;; extracting the archive.  Do not include /root
                            ;; because the root account might have a different
                            ;; home directory.
                            "./var/guix"
                            (string-append "." (%store-directory)))))))

    (gexp->derivation "guix-tarball.tar.xz" build
                      #:references-graphs `(("profile" ,profile))
                      #:modules '((guix build utils)
                                  (guix build store-copy)
                                  (gnu build install)))))


(define (log-to-info)
  "Return a script that spawns the Info reader on the right section of the
manual."
  (gexp->script "log-to-info"
                #~(begin
                    ;; 'gunzip' is needed to decompress the doc.
                    (setenv "PATH" (string-append #$gzip "/bin"))

                    (execl (string-append #$texinfo-4 "/bin/info") "info"
                           "-d" "/run/current-system/profile/share/info"
                           "-f" (string-append #$guix "/share/info/guix.info")
                           "-n" "System Installation"))))

(define %backing-directory
  ;; Sub-directory used as the backing store for copy-on-write.
  "/tmp/guix-inst")

(define (make-cow-store target)
  "Return a gexp that makes the store copy-on-write, using TARGET as the
backing store.  This is useful when TARGET is on a hard disk, whereas the
current store is on a RAM disk."
  (define (unionfs read-only read-write mount-point)
    ;; Make MOUNT-POINT the union of READ-ONLY and READ-WRITE.

    ;; Note: in the command below, READ-WRITE appears before READ-ONLY so that
    ;; it is considered a "higher-level branch", as per unionfs-fuse(8),
    ;; thereby allowing files existing on READ-ONLY to be copied over to
    ;; READ-WRITE.
    #~(fork+exec-command
       (list (string-append #$unionfs-fuse "/bin/unionfs")
             "-o"
             "cow,allow_other,use_ino,max_files=65536,nonempty"
             (string-append #$read-write "=RW:" #$read-only "=RO")
             #$mount-point)))

  (define (set-store-permissions directory)
    ;; Set the right perms on DIRECTORY to use it as the store.
    #~(begin
        (chown #$directory 0 30000)             ;use the fixed 'guixbuild' GID
        (chmod #$directory #o1775)))

  #~(begin
      (unless (file-exists? "/.ro-store")
        (mkdir "/.ro-store")
        (mount #$(%store-prefix) "/.ro-store" "none"
               (logior MS_BIND MS_RDONLY)))

      (let ((rw-dir (string-append target #$%backing-directory)))
        (mkdir-p rw-dir)
        (mkdir-p "/.rw-store")
        #$(set-store-permissions #~rw-dir)
        #$(set-store-permissions "/.rw-store")

        ;; Mount the union, then atomically make it the store.
        (and #$(unionfs "/.ro-store" #~rw-dir "/.rw-store")
             (begin
               (sleep 1) ;XXX: wait for unionfs to be ready
               (mount "/.rw-store" #$(%store-prefix) "" MS_MOVE)
               (rmdir "/.rw-store"))))))

(define (cow-store-service)
  "Return a service that makes the store copy-on-write, such that writes go to
the user's target storage device rather than on the RAM disk."
  ;; See <http://bugs.gnu.org/18061> for the initial report.
  (with-monad %store-monad
    (return (service
             (requirement '(root-file-system user-processes))
             (provision '(cow-store))
             (documentation
              "Make the store copy-on-write, with writes going to \
the given target.")

             ;; This is meant to be explicitly started by the user.
             (auto-start? #f)

             (start #~(case-lambda
                        ((target)
                         #$(make-cow-store #~target)
                         target)
                        (else
                         ;; Do nothing, and mark the service as stopped.
                         #f)))
             (stop #~(lambda (target)
                       ;; Delete the temporary directory, but leave everything
                       ;; mounted as there may still be processes using it
                       ;; since 'user-processes' doesn't depend on us.  The
                       ;; 'user-unmount' service will unmount TARGET
                       ;; eventually.
                       (delete-file-recursively
                        (string-append target #$%backing-directory))))))))

(define (configuration-template-service)
  "Return a dummy service whose purpose is to install an operating system
configuration template file in the installation system."

  (define search
    (cut search-path %load-path <>))
  (define templates
    (map (match-lambda
           ((file '-> target)
            (list (local-file (search file))
                  (string-append "/etc/configuration/" target))))
         '(("gnu/system/examples/bare-bones.tmpl" -> "bare-bones.scm")
           ("gnu/system/examples/desktop.tmpl" -> "desktop.scm"))))

  (with-monad %store-monad
    (return (service
             (requirement '(root-file-system))
             (provision '(os-config-template))
             (documentation
              "This dummy service installs an OS configuration template.")
             (start #~(const #t))
             (stop  #~(const #f))
             (activate
              #~(begin
                  (use-modules (ice-9 match)
                               (guix build utils))

                  (mkdir-p "/etc/configuration")
                  (for-each (match-lambda
                              ((file target)
                               (unless (file-exists? target)
                                 (copy-file file target))))
                            '#$templates)))))))

(define %nscd-minimal-caches
  ;; Minimal in-memory caching policy for nscd.
  (list (nscd-cache (database 'hosts)
                    (positive-time-to-live (* 3600 12))
                    (negative-time-to-live 20)
                    (persistent? #f)
                    (max-database-size (* 5 (expt 2 20)))))) ;5 MiB

(define (installation-services)
  "Return the list services for the installation image."
  (let ((motd (text-file "motd" "
Welcome to the installation of the Guix System Distribution!

There is NO WARRANTY, to the extent permitted by law.  In particular, you may
LOSE ALL YOUR DATA as a side effect of the installation process.  Furthermore,
it is alpha software, so it may BREAK IN UNEXPECTED WAYS.

You have been warned.  Thanks for being so brave.
")))
    (define (normal-tty tty)
      (mingetty-service tty
                        #:motd motd
                        #:auto-login "root"
                        #:login-pause? #t))

    (list (mingetty-service "tty1"
                            #:motd motd
                            #:auto-login "root")

          ;; Documentation.  The manual is in UTF-8, but
          ;; 'console-font-service' sets up Unicode support and loads a font
          ;; with all the useful glyphs like em dash and quotation marks.
          (mingetty-service "tty2"
                            #:motd motd
                            #:auto-login "guest"
                            #:login-program (log-to-info))

          ;; Documentation add-on.
          (configuration-template-service)

          ;; A bunch of 'root' ttys.
          (normal-tty "tty3")
          (normal-tty "tty4")
          (normal-tty "tty5")
          (normal-tty "tty6")

          ;; The usual services.
          (syslog-service)

          ;; The build daemon.  Register the hydra.gnu.org key as trusted.
          ;; This allows the installation process to use substitutes by
          ;; default.
          (guix-service #:authorize-hydra-key? #t)

          ;; Start udev so that useful device nodes are available.
          ;; Use device-mapper rules for cryptsetup & co; enable the CRDA for
          ;; regulations-compliant WiFi access.
          (udev-service #:rules (list lvm2 crda))

          ;; Add the 'cow-store' service, which users have to start manually
          ;; since it takes the installation directory as an argument.
          (cow-store-service)

          ;; Install Unicode support and a suitable font.
          (console-font-service "tty1")
          (console-font-service "tty2")
          (console-font-service "tty3")
          (console-font-service "tty4")
          (console-font-service "tty5")
          (console-font-service "tty6")

          ;; Since this is running on a USB stick with a unionfs as the root
          ;; file system, use an appropriate cache configuration.
          (nscd-service (nscd-configuration
                         (caches %nscd-minimal-caches))))))

(define %issue
  ;; Greeting.
  "
This is an installation image of the GNU system.  Welcome.

Use Alt-F2 for documentation.
")

(define installation-os
  ;; The operating system used on installation images for USB sticks etc.
  (operating-system
    (host-name "gnu")
    (timezone "Europe/Paris")
    (locale "en_US.utf8")
    (bootloader (grub-configuration
                 (device "/dev/sda")))
    (file-systems
     ;; Note: the disk image build code overrides this root file system with
     ;; the appropriate one.
     (cons (file-system
             (mount-point "/")
             (device "gnu-disk-image")
             (type "ext4"))
           %base-file-systems))

    (users (list (user-account
                  (name "guest")
                  (group "users")
                  (supplementary-groups '("wheel"))  ; allow use of sudo
                  (password "")
                  (comment "Guest of GNU")
                  (home-directory "/home/guest"))))

    (issue %issue)

    (services (installation-services))

    ;; We don't need setuid programs so pass the empty list so we don't pull
    ;; additional programs here.
    (setuid-programs '())

    (pam-services
     ;; Explicitly allow for empty passwords.
     (base-pam-services #:allow-empty-passwords? #t))

    (packages (cons* texinfo-4                 ;for the standalone Info reader
                     parted ddrescue
                     grub                  ;mostly so xrefs to its manual work
                     cryptsetup
                     wireless-tools iw wpa-supplicant-light iproute
                     ;; XXX: We used to have GNU fdisk here, but as of version
                     ;; 2.0.0a, that pulls Guile 1.8, which takes unreasonable
                     ;; space; furthermore util-linux's fdisk is already
                     ;; available here, so we keep that.
                     bash-completion
                     %base-packages))))

;; Return it here so 'guix system' can consume it directly.
installation-os

;;; install.scm ends here
