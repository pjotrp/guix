;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013, 2015 Andreas Enge <andreas@enge.fr>
;;; Copyright © 2013 Aljosha Papsch <misc@rpapsch.de>
;;; Copyright © 2014, 2015 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2014, 2015 Mark H Weaver <mhw@netris.org>
;;; Copyright © 2015 Ricardo Wurmus <rekado@elephly.net>
;;; Copyright © 2015 Taylan Ulrich Bayırlı/Kammer <taylanbayirli@gmail.com>
;;; Copyright © 2015 Eric Bavier <bavier@member.fsf.org>
;;; Copyright © 2015 Eric Dvorsak <eric@dvorsak.fr>
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

(define-module (gnu packages web)
  #:use-module (ice-9 match)
  #:use-module ((guix licenses) #:prefix l:)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix cvs-download)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system perl)
  #:use-module (guix build-system cmake)
  #:use-module (guix build-system r)
  #:use-module (gnu packages)
  #:use-module (gnu packages apr)
  #:use-module (gnu packages asciidoc)
  #:use-module (gnu packages docbook)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages cyrus-sasl)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages mit-krb5)
  #:use-module (gnu packages gd)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages icu4c)
  #:use-module (gnu packages lua)
  #:use-module (gnu packages base)
  #:use-module (gnu packages python)
  #:use-module (gnu packages pcre)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages xml)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages texinfo)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages statistics))

(define-public httpd
  (package
    (name "httpd")
    (version "2.4.16")
    (source (origin
             (method url-fetch)
             (uri (string-append "mirror://apache/httpd/httpd-"
                                 version ".tar.bz2"))
             (sha256
              (base32
               "0hrpy6gjwma0kba7p7m61vwh82qcnkf08123lrwpg257m93hnrmc"))))
    (build-system gnu-build-system)
    (inputs `(("apr" ,apr)
              ("apr-util" ,apr-util)
              ("openssl" ,openssl)
              ("pcre" ,pcre)
              ("perl" ,perl))) ; needed to run bin/apxs
    (arguments
     `(#:test-target "test"
       #:configure-flags (list "--enable-rewrite"
                               "--enable-userdir"
                               "--enable-vhost-alias"
                               "--enable-ssl"
                               "--enable-mime-magic"
                               (string-append "--sysconfdir="
                                              (assoc-ref %outputs "out")
                                              "/etc/httpd"))))
    (synopsis "Featureful HTTP server")
    (description
     "The Apache HTTP Server Project is a collaborative software development
effort aimed at creating a robust, commercial-grade, featureful, and
freely-available source code implementation of an HTTP (Web) server.  The
project is jointly managed by a group of volunteers located around the world,
using the Internet and the Web to communicate, plan, and develop the server
and its related documentation.")
    (license l:asl2.0)
    (home-page "https://httpd.apache.org/")))

(define-public nginx
  (package
    (name "nginx")
    (version "1.8.0")
    (source (origin
              (method url-fetch)
              (uri (string-append "http://nginx.org/download/nginx-"
                                  version ".tar.gz"))
              (sha256
               (base32
                "1mgkkmmwkhmpn68sdvbd73ssv6lpqhh864fsyvc1ij4hk4is3k13"))))
    (build-system gnu-build-system)
    (inputs `(("pcre" ,pcre)
              ("openssl" ,openssl)
              ("zlib" ,zlib)))
    (arguments
     `(#:tests? #f                      ; no test target
       #:phases
       (modify-phases %standard-phases
         (add-before 'configure 'patch-/bin/sh
           (lambda _
             (substitute* "auto/feature"
               (("/bin/sh") (which "bash")))))
         (replace 'configure
           (lambda* (#:key outputs #:allow-other-keys)
             (let ((flags
                    (list (string-append "--prefix=" (assoc-ref outputs "out"))
                          "--with-http_ssl_module"
                          "--with-pcre-jit"
                          "--with-ipv6"
                          "--with-debug"
                          ;; Even when not cross-building, we pass the
                          ;; --crossbuild option to avoid customizing for the
                          ;; kernel version on the build machine.
                          ,(let ((system "Linux")    ; uname -s
                                 (release "2.6.32")  ; uname -r
                                 ;; uname -m
                                 (machine (match (or (%current-target-system)
                                                     (%current-system))
                                            ("x86_64-linux"   "x86_64")
                                            ("i686-linux"     "i686")
                                            ("mips64el-linux" "mips64")
                                            ;; Prevent errors when querying
                                            ;; this package on unsupported
                                            ;; platforms, e.g. when running
                                            ;; "guix package --search="
                                            (_                "UNSUPPORTED"))))
                             (string-append "--crossbuild="
                                            system ":" release ":" machine)))))
               (setenv "CC" "gcc")
               (format #t "environment variable `CC' set to `gcc'~%")
               (format #t "configure flags: ~s~%" flags)
               (zero? (apply system* "./configure" flags)))))
         (add-after 'install 'fix-root-dirs
           (lambda* (#:key outputs #:allow-other-keys)
             ;; 'make install' puts things in strange places, so we need to
             ;; clean it up ourselves.
             (let* ((out (assoc-ref outputs "out"))
                    (share (string-append out "/share/nginx")))
               ;; This directory is empty, so get rid of it.
               (rmdir (string-append out "/logs"))
               ;; Example configuration and HTML files belong in
               ;; /share.
               (mkdir-p share)
               (rename-file (string-append out "/conf")
                            (string-append share "/conf"))
               (rename-file (string-append out "/html")
                            (string-append share "/html"))))))))
    (home-page "http://nginx.org")
    (synopsis "HTTP and reverse proxy server")
    (description
     "Nginx (\"engine X\") is a high-performance web and reverse proxy server
created by Igor Sysoev.  It can be used both as a standalone web server
and as a proxy to reduce the load on back-end HTTP or mail servers.")
    ;; Almost all of nginx is distributed under the bsd-2 license.
    ;; The exceptions are:
    ;;   * The 'nginx-http-push' module is covered by the expat license.
    ;;   * The 'nginx-development-kit' module is mostly covered by bsd-3,
    ;;     except for two source files which are bsd-4 licensed.
    (license (list l:bsd-2 l:expat l:bsd-3 l:bsd-4))))

(define-public starman
  (package
    (name "starman")
    (version "0.4011")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/M/MI/MIYAGAWA/"
                           "Starman-" version ".tar.gz"))
       (sha256
        (base32
         "1337zhi6v1sg4gd9rs3giybc7g1ysw8ak2da0vy098k4dacxyb57"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-libwww" ,perl-libwww)
       ("perl-module-build-tiny" ,perl-module-build-tiny)
       ("perl-test-requires" ,perl-test-requires)))
    (propagated-inputs
     `(("perl-data-dump" ,perl-data-dump)
       ("perl-http-date" ,perl-http-date)
       ("perl-http-message" ,perl-http-message)
       ("perl-http-parser-xs" ,perl-http-parser-xs)
       ("perl-net-server" ,perl-net-server)
       ("perl-plack" ,perl-plack)
       ("perl-test-tcp" ,perl-test-tcp)))
    (home-page "http://search.cpan.org/dist/Starman")
    (synopsis "PSGI/Plack web server")
    (description "Starman is a PSGI perl web server that has unique features
such as high performance, preforking, signal support, superdaemon awareness,
and UNIX socket support.")
    (license (package-license perl))))

(define-public jansson
  (package
    (name "jansson")
    (version "2.7")
    (source (origin
             (method url-fetch)
             (uri
              (string-append "http://www.digip.org/jansson/releases/jansson-"
                             version ".tar.gz"))
             (sha256
              (base32
               "1mvq9p85khsl818i4vbszyfab0fd45mdrwrxjkzw05mk1xcyc1br"))))
    (build-system gnu-build-system)
    (home-page "http://www.digip.org/jansson/")
    (synopsis "JSON C library")
    (description
     "Jansson is a C library for encoding, decoding and manipulating JSON
data.")
    (license l:expat)))

(define-public json-c
  (package
    (name "json-c")
    (version "0.12")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "https://s3.amazonaws.com/json-c_releases/releases/json-c-"
                   version ".tar.gz"))
             (sha256
              (base32
               "0gwzic3ifg2d0w32ya3agpxh8i083cgvf7kmc51cnbgqnfr02300"))
             (modules '((guix build utils)))
             (snippet
              '(begin
                 ;; Somehow 'config.h.in' is older than
                 ;; 'aclocal.m4', which would trigger a rule to
                 ;; run 'autoheader'.
                 (set-file-time "config.h.in"
                                (stat "aclocal.m4"))

                 ;; Don't try to build with -Werror.
                 (substitute* (find-files "." "Makefile\\.in")
                   (("-Werror") ""))))))
    (build-system gnu-build-system)
    (arguments '(#:parallel-build? #f
                 #:parallel-tests? #f))
    (home-page "https://github.com/json-c/json-c/wiki")
    (synopsis "JSON implementation in C")
    (description
     "JSON-C implements a reference counting object model that allows you to
easily construct JSON objects in C, output them as JSON formatted strings and
parse JSON formatted strings back into the C representation of JSON objects.")
    (license l:x11)))

(define-public rapidjson
  (package
    (name "rapidjson")
    (version "1.0.2")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "https://github.com/miloyip/rapidjson/archive/v"
                   version ".tar.gz"))
             (file-name (string-append name "-" version ".tar.gz"))
             (sha256
              (base32
               "0rl6s0vg5y1dhh9vfl1lqay3sxf69sxjh0czxrjmasn7ng91wwf3"))
             (modules '((guix build utils)))
             (snippet
              ;; Building with GCC 4.8 with -Werror was fine, but 4.9.3
              ;; complains in new ways, so turn of -Werror.
              '(substitute* (find-files "." "^CMakeLists\\.txt$")
                 (("-Werror") "")))))
    (build-system cmake-build-system)
    (home-page "https://github.com/miloyip/rapidjson")
    (synopsis "JSON parser/generator for C++ with both SAX/DOM style API")
    (description
     "RapidJSON is a fast JSON parser/generator for C++ with both SAX/DOM
style API.")
    (license l:expat)))

(define-public libyajl
  (package
    (name "libyajl")
    (version "2.1.0")
    (source (origin
              (method url-fetch)
              (uri (string-append "https://github.com/lloyd/yajl/"
                                  "archive/" version ".tar.gz"))
              (file-name (string-append name "-" version ".tar.gz"))
              (sha256
               (base32
                "0nmcqpaiq4pv7dymyg3n3jsd57yhp5npxl26a1hzw3m3lmj37drz"))))
    (build-system cmake-build-system)
    (home-page "https://lloyd.github.io/yajl/")
    (synopsis "C library for parsing JSON")
    (description
     "Yet Another JSON Library (YAJL) is a small event-driven (SAX-style) JSON
parser written in ANSI C and a small validating JSON generator.")
    (license l:isc)))

(define-public libwebsockets
  (package
    (name "libwebsockets")
    (version "1.3")
    (source (origin
              ;; The project does not publish tarballs, so we have to take
              ;; things from Git.
              (method git-fetch)
              (uri (git-reference
                    (url "git://git.libwebsockets.org/libwebsockets")
                    (commit (string-append "v" version
                                           "-chrome37-firefox30"))))
              (sha256
               (base32
                "12fqh2d2098mgf0ls19p9lzibpsqhv7mc5rn1yvrbfnazmcr40g4"))
              (file-name (string-append name "-" version))))

    (build-system cmake-build-system)
    (arguments
     ;; XXX: The thing lacks a 'make test' target, because CMakeLists.txt
     ;; doesn't use 'add_test', and it's unclear how to run the test suite.
     '(#:tests? #f))

    (native-inputs `(("perl" ,perl)))             ; to build the HTML doc
    (inputs `(("zlib" ,zlib)
              ("openssl" ,openssl)))
    (synopsis "WebSockets library written in C")
    (description
     "Libwebsockets is a library that allows C programs to establish client
and server WebSockets connections---a protocol layered above HTTP that allows
for efficient socket-like bidirectional reliable communication channels.")
    (home-page "http://libwebsockets.org/")

    ;; This is LGPLv2.1-only with extra exceptions specified in 'LICENSE'.
    (license l:lgpl2.1)))

(define-public libpsl
  (package
    (name "libpsl")
    (version "0.7.1")
    (source (origin
              (method url-fetch)
              (uri (string-append "https://github.com/rockdaboot/libpsl/"
                                  "archive/libpsl-" version ".tar.gz"))
              (sha256
               (base32
                "1k0klj668c9v0r4993vfs3kq773mzdz61vsigqw6v1mjcwnf1si3"))))
    (build-system gnu-build-system)
    (inputs `(("icu4c" ,icu4c)))
    ;; The release tarball lacks the generated files.
    (native-inputs `(("autoconf" ,autoconf)
                     ("automake" ,automake)
                     ("gettext"  ,gnu-gettext)
                     ("which"    ,which)
                     ("libtool"  ,libtool)
                     ("pkg-config" ,pkg-config)))
    (arguments
     `(#:phases (alist-cons-after
                 'unpack 'bootstrap
                 (lambda _
                   (zero? (system* "sh" "autogen.sh")))
                 %standard-phases)))
    (home-page "https://github.com/rockdaboot/libpsl")
    (synopsis "C library for the Publix Suffix List")
    (description
     "A \"public suffix\" is a domain name under which Internet users can
directly register own names.

Browsers and other web clients can use it to avoid privacy-leaking
\"supercookies\", avoid privacy-leaking \"super domain\" certificates, domain
highlighting parts of the domain in a user interface, and sorting domain lists
by site.

Libpsl has built-in PSL data for fast access, allows to load PSL data from
files, checks if a given domain is a public suffix, provides immediate cookie
domain verification, finds the longest public part of a given domain, finds
the shortest private part of a given domain, works with international
domains (UTF-8 and IDNA2008 Punycode), is thread-safe, and handles IDNA2008
UTS#46.")
    (license l:x11)))

(define-public tidy
  (package
    (name "tidy")
    (version "20091223")
    (source (origin
              (method cvs-fetch)
              (uri (cvs-reference
                    (root-directory
                     ":pserver:anonymous@tidy.cvs.sourceforge.net:/cvsroot/tidy")
                    (module "tidy")
                    (revision "2009-12-23")))
              (sha256
               (base32
                "14dsnmirjcrvwsffqp3as70qr6bbfaig2fv3zvs5g7005jrsbvpb"))
              (patches (list (search-patch "tidy-CVE-2015-5522+5523.patch")))))
    (build-system gnu-build-system)
    (arguments
     '(#:phases (alist-cons-after
                 'unpack 'bootstrap
                 (lambda* (#:key inputs #:allow-other-keys)
                   ;; configure.in and Makefile.am aren't in the root of the
                   ;; source tree.
                   (copy-recursively "build/gnuauto" ".")
                   (setenv "AUTOMAKE" "automake --foreign")
                   (zero? (system* "autoreconf" "-vfi")))
                 %standard-phases)))
    (native-inputs
     `(("automake" ,automake)
       ("autoconf" ,autoconf)
       ("libtool" ,libtool)))
    (synopsis "HTML validator and tidier")
    (description "HTML Tidy is a command-line tool and C library that can be
used to validate and fix HTML data.")
    (home-page "http://tidy.sourceforge.net/")
    (license (l:x11-style "file:///include/tidy.h"))))

(define-public tinyproxy
  (package
    (name "tinyproxy")
    (version "1.8.3")
    (source (origin
              (method url-fetch)
              (uri (string-append
                    "http://www.samba.org/~obnox/" name "/download/"
                    name "-" version ".tar.bz2"))
              (sha256
               (base32
                "0vl9igw7vm924rs6d6bkib7zfclxnlf9s8rmml1sfwj7xda9nmdy"))))
    (build-system gnu-build-system)
    (arguments
     `(#:configure-flags
       (list
        ;; For the log file, etc.
        "--localstatedir=/var")
       #:phases
       (alist-cons-before
        'build 'pre-build
        (lambda* (#:key inputs #:allow-other-keys #:rest args)
          ;; Uncommenting the next two lines may assist in debugging
          ;; (substitute* "docs/man5/Makefile" (("a2x") "a2x -v"))
          ;; (setenv "XML_DEBUG_CATALOG" "1")
          #t)
        %standard-phases)))
    ;; All of the below are used to generate the documentation
    ;; (Should they be propagated inputs of asciidoc ??)
    (native-inputs `(("asciidoc" ,asciidoc)
                     ("libxml2" ,libxml2)
                     ("docbook-xml" ,docbook-xml)
                     ("docbook-xsl" ,docbook-xsl)
                     ("libxslt" ,libxslt)))
    (home-page "https://banu.com/tinyproxy/")
    (synopsis "Light-weight HTTP/HTTPS proxy daemon")
    (description "Tinyproxy is a light-weight HTTP/HTTPS proxy
daemon.  Designed from the ground up to be fast and yet small, it is an ideal
solution for use cases such as embedded deployments where a full featured HTTP
proxy is required, but the system resources for a larger proxy are
unavailable.")
    (license l:gpl2+)))

(define-public polipo
  (package
    (name "polipo")
    (version "1.1.1")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "http://www.pps.univ-paris-diderot.fr/~jch/software/files/polipo/polipo-"
             version ".tar.gz"))
       (sha256
        (base32
         "05g09sg9qkkhnc2mxldm1w1xkxzs2ylybkjzs28w8ydbjc3pand2"))))
    (native-inputs `(("texinfo" ,texinfo)))
    (build-system gnu-build-system)
    (arguments
     `(#:phases
       (alist-delete 'configure %standard-phases)
       #:make-flags (let ((out (assoc-ref %outputs "out")))
                      (list (string-append "PREFIX=" out)
                            (string-append "LOCAL_ROOT="
                                           out "/share/polipo/www")
                            "CC=gcc"))
       ;; No 'check' target.
       #:tests? #f))
    (home-page "http://www.pps.univ-paris-diderot.fr/~jch/software/polipo/")
    (synopsis "Small caching web proxy")
    (description
     "Polipo is a small caching web proxy (web cache, HTTP proxy, and proxy
server).  It was primarily designed to be used by one person or a small group
of people.")
    (license l:expat)))

(define-public libyaml
  (package
    (name "libyaml")
    (version "0.1.5")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "http://pyyaml.org/download/libyaml/yaml-"
             version ".tar.gz"))
       (sha256
        (base32
         "1vrv5ly58bkmcyc049ad180f2m8iav6l9h3v8l2fqdmrny7yx1zs"))))
    (build-system gnu-build-system)
    (home-page "http://pyyaml.org/wiki/LibYAML")
    (synopsis "YAML 1.1 parser and emitter written in C")
    (description
     "LibYAML is a YAML 1.1 parser and emitter written in C.")
    (license l:expat)))

(define-public libquvi-scripts
  (package
    (name "libquvi-scripts")
    (version "0.4.21")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "mirror://sourceforge/quvi/libquvi-scripts-" version ".tar.xz"))
       (sha256
        (base32 "0d0giry6bb57pnidymvdl7i5x9bq3ljk3g4bs294hcr5mj3cq0kw"))))
    (build-system gnu-build-system)
    (home-page "http://quvi.sourceforge.net/")
    (synopsis "Media stream URL parser")
    (description "This package contains support scripts called by libquvi to
parse media stream properties.")
    (license l:lgpl2.1+)))

(define-public libquvi
  (package
    (name "libquvi")
    (version "0.4.1")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "mirror://sourceforge/quvi/libquvi-" version ".tar.xz"))
       (sha256
        (base32 "00x9gbmzc5cns0gnfag0hsphcr3cb33vbbb9s7ppvvd6bxz2z1mm"))))
    (build-system gnu-build-system)
    (native-inputs `(("pkg-config" ,pkg-config)))
    (inputs
     `(("curl" ,curl)
       ("cyrus-sasl" ,cyrus-sasl)
       ("libquvi-scripts" ,libquvi-scripts)
       ("lua" ,lua-5.1)
       ("openssl" ,openssl)
       ("zlib" ,zlib)))
    (arguments
     ;; Lua provides no .pc file, so add CFLAGS/LIBS manually.
     '(#:configure-flags
       (let ((lua (assoc-ref %build-inputs "lua")))
         (list
          (string-append "liblua_CFLAGS=-I" lua "/include")
          (string-append "liblua_LIBS=-L" lua "/libs -llua")))))
    (home-page "http://quvi.sourceforge.net/")
    (synopsis "Media stream URL parser")
    (description "libquvi is a library with a C API for parsing media stream
URLs and extracting their actual media files.")
    (license l:lgpl2.1+)))

(define-public quvi
  (package
    (name "quvi")
    (version "0.4.2")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "mirror://sourceforge/quvi/quvi-" version ".tar.xz"))
       (sha256
        (base32 "09lhl6dv5zpryasx7yjslfrcdcqlsbwapvd5lg7w6sm5x5n3k8ci"))))
    (build-system gnu-build-system)
    (native-inputs `(("pkg-config" ,pkg-config)))
    (inputs
     `(("curl" ,curl)
       ("libquvi" ,libquvi)))
    (home-page "http://quvi.sourceforge.net/")
    (synopsis "Media stream URL parser")
    (description "quvi is a command-line-tool suite to extract media files
from streaming URLs.  It is a command-line wrapper for the libquvi library.")
    (license l:lgpl2.1+)))

(define-public serf
  (package
    (name "serf")
    (version "1.3.8")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "http://serf.googlecode.com/svn/src_releases/serf-"
                           version ".tar.bz2"))
       (sha256
        (base32 "14155g48gamcv5s0828bzij6vr14nqmbndwq8j8f9g6vcph0nl70"))
       (patches (map search-patch '("serf-comment-style-fix.patch"
                                    "serf-deflate-buckets-test-fix.patch")))
       (patch-flags '("-p0"))))
    (build-system gnu-build-system)
    (native-inputs
     `(("scons" ,scons)
       ("python" ,python-2)))
    (propagated-inputs
     `(("apr" ,apr)
       ("apr-util" ,apr-util)
       ("openssl" ,openssl)))
    (inputs
     `(;; TODO: Fix build with gss.
       ;;("gss" ,gss)
       ("zlib" ,zlib)))
    (arguments
     `(#:phases
       ;; TODO: Add scons-build-system and use it here.
       (modify-phases %standard-phases
         (delete 'configure)
         (add-after 'unpack 'scons-propagate-environment
                    (lambda _
                      ;; By design, SCons does not, by default, propagate
                      ;; environment variables to subprocesses.  See:
                      ;; <http://comments.gmane.org/gmane.linux.distributions.nixos/4969>
                      ;; Here, we modify the SConstruct file to arrange for
                      ;; environment variables to be propagated.
                      (substitute* "SConstruct"
                        (("^env = Environment\\(")
                         "env = Environment(ENV=os.environ, "))))
         (replace 'build
                  (lambda* (#:key inputs outputs #:allow-other-keys)
                    (let ((out      (assoc-ref outputs "out"))
                          (apr      (assoc-ref inputs "apr"))
                          (apr-util (assoc-ref inputs "apr-util"))
                          (openssl  (assoc-ref inputs "openssl"))
                          ;;(gss      (assoc-ref inputs "gss"))
                          (zlib     (assoc-ref inputs "zlib")))
                      (zero? (system* "scons"
                                      (string-append "APR=" apr)
                                      (string-append "APU=" apr-util)
                                      (string-append "OPENSSL=" openssl)
                                      ;;(string-append "GSSAPI=" gss)
                                      (string-append "ZLIB=" zlib)
                                      (string-append "PREFIX=" out))))))
         (replace 'check   (lambda _ (zero? (system* "scons" "check"))))
         (replace 'install (lambda _ (zero? (system* "scons" "install")))))))
    (home-page "https://code.google.com/p/serf/")
    (synopsis "High-performance asynchronous HTTP client library")
    (description
     "serf is a C-based HTTP client library built upon the Apache Portable
Runtime (APR) library.  It multiplexes connections, running the read/write
communication asynchronously.  Memory copies and transformations are kept to a
minimum to provide high performance operation.")
    ;; Most of the code is covered by the Apache License, Version 2.0, but the
    ;; bundled CuTest framework uses a different non-copyleft license.
    (license (list l:asl2.0 (l:non-copyleft "file://test/CuTest-README.txt")))))

(define-public sassc
  ;; libsass must be statically linked and it isn't included in the sassc
  ;; release tarballs, hence this odd package recipe.
  (let* ((version "3.2.5")
         (libsass
          (origin
            (method url-fetch)
            (uri (string-append
                  "https://github.com/sass/libsass/archive/"
                  version ".tar.gz"))
            (file-name (string-append "libsass-" version ".tar.gz"))
            (sha256
             (base32
              "1x25k6p1s1yzsdpzb7bzh8japilmi1mk3z96q66pycbinj9z9is4")))))
    (package
      (name "sassc")
      (version version)
      (source (origin
                (method url-fetch)
                (uri (string-append "https://github.com/sass/sassc/archive/"
                                    version ".tar.gz"))
                (file-name (string-append "sassc-" version ".tar.gz"))
                (sha256
                 (base32
                  "1xf3w75w840rj0nx375rxi7mcv1ngqqq8p3zrzjlyx8jfpnldmv5"))))
      (build-system gnu-build-system)
      (arguments
       `(#:make-flags '("CC=gcc")
         #:test-target "test"
         #:phases
         (modify-phases %standard-phases
           (delete 'configure)
           (add-after 'unpack 'unpack-libsass-and-set-path
             (lambda* (#:key inputs #:allow-other-keys)
               (and (zero? (system* "tar" "xvf" (assoc-ref inputs "libsass")))
                    (begin
                      (setenv "SASS_LIBSASS_PATH"
                              (string-append (getcwd) "/libsass-" ,version))
                      #t))))
           (replace 'install ; no install target
             (lambda* (#:key outputs #:allow-other-keys)
               (let ((bin (string-append (assoc-ref outputs "out") "/bin")))
                 (mkdir-p bin)
                 (copy-file "bin/sassc" (string-append bin "/sassc"))
                 #t))))))
      (inputs
       `(("libsass" ,libsass)))
      (synopsis "CSS pre-processor")
      (description "SassC is a compiler written in C for the CSS pre-processor
language known as SASS.")
      (home-page "http://sass-lang.com/libsass")
      (license l:expat))))


(define-public perl-apache-logformat-compiler
  (package
    (name "perl-apache-logformat-compiler")
    (version "0.32")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/K/KA/KAZEBURO/"
                           "Apache-LogFormat-Compiler-" version ".tar.gz"))
       (sha256
        (base32
         "0zyx4r2bxc6d48m70fhcq80nw0q9wnfz6qgn1g0r6bigqgdjq4dw"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-http-message" ,perl-http-message)
       ("perl-test-mocktime" ,perl-test-mocktime)
       ("perl-try-tiny" ,perl-try-tiny)
       ("perl-uri" ,perl-uri)))
    (propagated-inputs
     `(("perl-posix-strftime-compiler" ,perl-posix-strftime-compiler)))
    (arguments `(#:tests? #f))          ;TODO: Timezone test failures
    (home-page "http://search.cpan.org/dist/Apache-LogFormat-Compiler")
    (synopsis "Compile a log format string to perl-code")
    (description "This module provides methods to compile a log format string
to perl-code, for faster generation of access_log lines.")
    (license (package-license perl))))

(define-public perl-authen-sasl
  (package
    (name "perl-authen-sasl")
    (version "2.16")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/G/GB/GBARR/"
                           "Authen-SASL-" version ".tar.gz"))
       (sha256
        (base32
         "02afhlrdq5hh5g8b32fa79fqq5i76qzwfqqvfi9zi57h31szl536"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-digest-hmac" ,perl-digest-hmac)
       ("perl-gssapi" ,perl-gssapi)))
    (home-page "http://search.cpan.org/dist/Authen-SASL")
    (synopsis "SASL authentication framework")
    (description "Authen::SASL provides an SASL authentication framework.")
    (license (package-license perl))))

(define-public perl-catalyst-action-renderview
  (package
    (name "perl-catalyst-action-renderview")
    (version "0.16")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/B/BO/BOBTFISH/"
                           "Catalyst-Action-RenderView-"
                           version ".tar.gz"))
       (sha256
        (base32
         "0j1rrld13cjk7ks92b5hv3xw4rfm2lvmksb4rlzd8mx0a0wj0rc5"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-http-request-ascgi" ,perl-http-request-ascgi)))
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-data-visitor" ,perl-data-visitor)
       ("perl-mro-compat" ,perl-mro-compat)))
    (home-page "http://search.cpan.org/dist/Catalyst-Action-RenderView")
    (synopsis "Sensible default Catalyst action")
    (description "This Catalyst action implements a sensible default end
action, which will forward to the first available view.")
    (license (package-license perl))))

(define-public perl-catalyst-action-rest
  (package
    (name "perl-catalyst-action-rest")
    (version "1.17")
    (source (origin
              (method url-fetch)
              (uri (string-append "mirror://cpan/authors/id/F/FR/FREW/"
                                  "Catalyst-Action-REST-" version ".tar.gz"))
              (sha256
               (base32
                "1rnxmsd9dsqz4xc0g9ynafxi934jwp0nixbg92q3bc2h46xcccy8"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-requires" ,perl-test-requires)))
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-class-inspector" ,perl-class-inspector)
       ("perl-libwww" ,perl-libwww)
       ("perl-moose" ,perl-moose)
       ("perl-mro-compat" ,perl-mro-compat)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)
       ("perl-params-validate" ,perl-params-validate)
       ("perl-uri-find" ,perl-uri-find)))
    (home-page "http://search.cpan.org/dist/Catalyst-Action-REST")
    (synopsis "Automated REST Method Dispatching")
    (description "This Action handles doing automatic method dispatching for
REST requests.  It takes a normal Catalyst action, and changes the dispatch to
append an underscore and method name.  First it will try dispatching to an
action with the generated name, and failing that it will try to dispatch to a
regular method.")
    (license (package-license perl))))

(define-public perl-catalyst-authentication-store-dbix-class
  (package
    (name "perl-catalyst-authentication-store-dbix-class")
    (version "0.1506")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/I/IL/ILMARI/"
                           "Catalyst-Authentication-Store-DBIx-Class-"
                           version ".tar.gz"))
       (sha256
        (base32
         "0i5ja7690fs9nhxcij6lw51j804sm8s06m5mvk1n8pi8jljrymvw"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-catalyst-plugin-authorization-roles"
        ,perl-catalyst-plugin-authorization-roles)
       ("perl-catalyst-plugin-session-state-cookie"
        ,perl-catalyst-plugin-session-state-cookie)
       ("perl-dbd-sqlite" ,perl-dbd-sqlite)
       ("perl-test-www-mechanize-catalyst" ,perl-test-www-mechanize-catalyst)))
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-catalyst-plugin-authentication"
        ,perl-catalyst-plugin-authentication)
       ("perl-dbix-class" ,perl-dbix-class)
       ("perl-catalyst-model-dbic-schema" ,perl-catalyst-model-dbic-schema)))
    (home-page
     "http://search.cpan.org/dist/Catalyst-Authentication-Store-DBIx-Class")
    (synopsis "Storage class for Catalyst authentication using DBIx::Class")
    (description "The Catalyst::Authentication::Store::DBIx::Class class
provides access to authentication information stored in a database via
DBIx::Class.")
    (license (package-license perl))))

(define-public perl-catalyst-component-instancepercontext
  (package
    (name "perl-catalyst-component-instancepercontext")
    (version "0.001001")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/G/GR/GRODITI/"
                           "Catalyst-Component-InstancePerContext-"
                           version ".tar.gz"))
       (sha256
        (base32
         "0wfj4vnn2cvk6jh62amwlg050p37fcwdgrn9amcz24z6w4qgjqvz"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-moose" ,perl-moose)))
    (home-page
     "http://search.cpan.org/dist/Catalyst-Component-InstancePerContext")
    (synopsis "Create only one instance of Moose component per context")
    (description "Catalyst::Component::InstancePerContext returns a new
instance of a component on each request.")
    (license (package-license perl))))

(define-public perl-catalyst-devel
  (package
    (name "perl-catalyst-devel")
    (version "1.39")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/I/IL/ILMARI/"
                           "Catalyst-Devel-" version ".tar.gz"))
       (sha256
        (base32
         "12m50bbkggjmpxihv3wnvr0g2qng0zwhlzi5ygppjz8wh2x73qxw"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-fatal" ,perl-test-fatal)))
    (propagated-inputs
     `(("perl-catalyst-action-renderview" ,perl-catalyst-action-renderview)
       ("perl-catalyst-plugin-configloader" ,perl-catalyst-plugin-configloader)
       ("perl-catalyst-plugin-static-simple" ,perl-catalyst-plugin-static-simple)
       ("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-config-general" ,perl-config-general)
       ("perl-file-changenotify" ,perl-file-changenotify)
       ("perl-file-copy-recursive" ,perl-file-copy-recursive)
       ("perl-file-sharedir" ,perl-file-sharedir)
       ("perl-module-install" ,perl-module-install)
       ("perl-moose" ,perl-moose)
       ("perl-moosex-emulate-class-accessor-fast"
        ,perl-moosex-emulate-class-accessor-fast)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)
       ("perl-namespace-clean" ,perl-namespace-clean)
       ("perl-path-class" ,perl-path-class)
       ("perl-template-toolkit" ,perl-template-toolkit)))
    (home-page "http://search.cpan.org/dist/Catalyst-Devel")
    (synopsis "Catalyst Development Tools")
    (description "The Catalyst-Devel distribution includes a variety of
modules useful for the development of Catalyst applications, but not required
to run them.  Catalyst-Devel includes the Catalyst::Helper system, which
autogenerates scripts and tests; Module::Install::Catalyst, a Module::Install
extension for Catalyst; and requirements for a variety of development-related
modules.")
    (license (package-license perl))))

(define-public perl-catalyst-dispatchtype-regex
  (package
    (name "perl-catalyst-dispatchtype-regex")
    (version "5.90035")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/M/MG/MGRIMES/"
                           "Catalyst-DispatchType-Regex-" version ".tar.gz"))
       (sha256
        (base32
         "06jq1lmpq88rmp9zik5gqczg234xac0hiyc3l698iif7zsgcyb80"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-module-build" ,perl-module-build) ;needs Module::Build >= 0.4004
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)
       ("perl-catalyst-runtime" ,perl-catalyst-runtime)))
    (propagated-inputs
     `(("perl-moose" ,perl-moose)
       ("perl-text-simpletable" ,perl-text-simpletable)))
    (home-page "http://search.cpan.org/dist/Catalyst-DispatchType-Regex")
    (synopsis "Regex DispatchType for Catalyst")
    (description "Dispatch type managing path-matching behaviour using
regexes.  Regex dispatch types have been deprecated and removed from Catalyst
core.  It is recommend that you use Chained methods or other techniques
instead.  As part of the refactoring, the dispatch priority of Regex vs Regexp
vs LocalRegex vs LocalRegexp may have changed.  Priority is now influenced by
when the dispatch type is first seen in your application.")
    (license (package-license perl))))

(define-public perl-catalyst-model-dbic-schema
  (package
  (name "perl-catalyst-model-dbic-schema")
  (version "0.65")
  (source
    (origin
      (method url-fetch)
      (uri (string-append "mirror://cpan/authors/id/G/GB/GBJK/"
                          "Catalyst-Model-DBIC-Schema-"
                          version ".tar.gz"))
      (sha256
        (base32
          "1spfjcjc0b9dv3k2gbanqj1m1cqzyxb32p76dhdwizzpbvpi3a96"))))
  (build-system perl-build-system)
  (native-inputs
   `(("perl-dbd-sqlite" ,perl-dbd-sqlite)
     ("perl-test-exception" ,perl-test-exception)
     ("perl-test-requires" ,perl-test-requires)))
  (propagated-inputs
   `(("perl-carp-clan" ,perl-carp-clan)
     ("perl-catalyst-component-instancepercontext"
      ,perl-catalyst-component-instancepercontext)
     ("perl-catalyst-runtime" ,perl-catalyst-runtime)
     ("perl-catalystx-component-traits" ,perl-catalystx-component-traits)
     ("perl-dbix-class" ,perl-dbix-class)
     ("perl-dbix-class-cursor-cached" ,perl-dbix-class-cursor-cached)
     ("perl-dbix-class-schema-loader" ,perl-dbix-class-schema-loader)
     ("perl-hash-merge" ,perl-hash-merge)
     ("perl-list-moreutils" ,perl-list-moreutils)
     ("perl-module-runtime" ,perl-module-runtime)
     ("perl-moose" ,perl-moose)
     ("perl-moosex-markasmethods" ,perl-moosex-markasmethods)
     ("perl-moosex-nonmoose" ,perl-moosex-nonmoose)
     ("perl-moosex-types" ,perl-moosex-types)
     ("perl-moosex-types-loadableclass" ,perl-moosex-types-loadableclass)
     ("perl-namespace-autoclean" ,perl-namespace-autoclean)
     ("perl-namespace-clean" ,perl-namespace-clean)
     ("perl-tie-ixhash" ,perl-tie-ixhash)
     ("perl-try-tiny" ,perl-try-tiny)))
  (home-page "http://search.cpan.org/dist/Catalyst-Model-DBIC-Schema")
  (synopsis "DBIx::Class::Schema Model Class")
  (description "This is a Catalyst Model for DBIx::Class::Schema-based
Models.")
  (license (package-license perl))))

(define-public perl-catalyst-plugin-accesslog
  (package
    (name "perl-catalyst-plugin-accesslog")
    (version "1.05")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/A/AR/ARODLAND/"
                           "Catalyst-Plugin-AccessLog-" version ".tar.gz"))
       (sha256
        (base32
         "0hqvckaw91q5yc25a33bp0d4qqxlgkp7rxlvi8n8svxd1406r55s"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-datetime" ,perl-datetime)
       ("perl-moose" ,perl-moose)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)))
    (arguments `(#:tests? #f))          ;Unexpected http responses
    (home-page "http://search.cpan.org/dist/Catalyst-Plugin-AccessLog")
    (synopsis "Request logging from within Catalyst")
    (description "This Catalyst plugin enables you to create \"access logs\"
from within a Catalyst application instead of requiring a webserver to do it
for you.  It will work even with Catalyst debug logging turned off.")
    (license (package-license perl))))

(define-public perl-catalyst-plugin-authentication
  (package
    (name "perl-catalyst-plugin-authentication")
    (version "0.10023")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/B/BO/BOBTFISH/"
                           "Catalyst-Plugin-Authentication-"
                           version ".tar.gz"))
       (sha256
        (base32
         "0v6hb4r1wv3djrnqvnjcn3xx1scgqzx8nyjdg9lfc1ybvamrl0rn"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-catalyst-plugin-session" ,perl-catalyst-plugin-session)
       ("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-class-inspector" ,perl-class-inspector)
       ("perl-moose" ,perl-moose)
       ("perl-moosex-emulate-class-accessor-fast"
        ,perl-moosex-emulate-class-accessor-fast)
       ("perl-mro-compat" ,perl-mro-compat)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)
       ("perl-string-rewriteprefix" ,perl-string-rewriteprefix)
       ("perl-test-exception" ,perl-test-exception)
       ("perl-try-tiny" ,perl-try-tiny)))
    (home-page "http://search.cpan.org/dist/Catalyst-Plugin-Authentication")
    (synopsis "Infrastructure plugin for the Catalyst authentication framework")
    (description "The authentication plugin provides generic user support for
Catalyst apps.  It is the basis for both authentication (checking the user is
who they claim to be), and authorization (allowing the user to do what the
system authorises them to do).")
    (license (package-license perl))))

(define-public perl-catalyst-plugin-authorization-roles
  (package
    (name "perl-catalyst-plugin-authorization-roles")
    (version "0.09")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/B/BO/BOBTFISH/"
                           "Catalyst-Plugin-Authorization-Roles-"
                           version ".tar.gz"))
       (sha256
        (base32
         "0l83lkwmq0lngwh8b1rv3r719pn8w1gdbyhjqm74rnd0wbjl8h7f"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-exception" ,perl-test-exception)))
    (propagated-inputs
     `(("perl-catalyst-plugin-authentication"
        ,perl-catalyst-plugin-authentication)
       ("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-set-object" ,perl-set-object)
       ("perl-universal-isa" ,perl-universal-isa)))
    (home-page
     "http://search.cpan.org/dist/Catalyst-Plugin-Authorization-Roles")
    (synopsis "Role-based authorization for Catalyst")
    (description "Catalyst::Plugin::Authorization::Roles provides role-based
authorization for Catalyst based on Catalyst::Plugin::Authentication.")
    (license (package-license perl))))

(define-public perl-catalyst-plugin-captcha
  (package
    (name "perl-catalyst-plugin-captcha")
    (version "0.04")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/D/DI/DIEGOK/"
                           "Catalyst-Plugin-Captcha-" version ".tar.gz"))
       (sha256
        (base32
         "0llyj3v5nx9cx46jdbbvxf1lc9s9cxq5ml22xmx3wkb201r5qgaa"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-catalyst-plugin-session" ,perl-catalyst-plugin-session)
       ("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-gd-securityimage" ,perl-gd-securityimage)
       ("perl-http-date" ,perl-http-date)))
    (home-page "http://search.cpan.org/dist/Catalyst-Plugin-Captcha")
    (synopsis "Captchas for Catalyst")
    (description "This plugin creates and validates Captcha images for
Catalyst.")
    (license (package-license perl))))

(define-public perl-catalyst-plugin-configloader
  (package
    (name "perl-catalyst-plugin-configloader")
    (version "0.34")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/B/BO/BOBTFISH/"
                           "Catalyst-Plugin-ConfigLoader-"
                           version ".tar.gz"))
       (sha256
        (base32
         "19j7p4v7mbx6wrmpvmrnd974apx7hdl2s095ga3b9zcbdrl77h5q"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-path-class" ,perl-path-class)))
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-config-any" ,perl-config-any)
       ("perl-data-visitor" ,perl-data-visitor)
       ("perl-mro-compat" ,perl-mro-compat)))
    (home-page "http://search.cpan.org/dist/Catalyst-Plugin-ConfigLoader")
    (synopsis "Load config files of various types")
    (description "This module will attempt to load find and load configuration
files of various types.  Currently it supports YAML, JSON, XML, INI and Perl
formats.")
    (license (package-license perl))))

(define-public perl-catalyst-plugin-session
  (package
    (name "perl-catalyst-plugin-session")
    (version "0.39")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/J/JJ/JJNAPIORK/"
                           "Catalyst-Plugin-Session-" version ".tar.gz"))
       (sha256
        (base32
         "0m4a003qgz7848iyckwbigg2vw3kmfxggh1razrnzxrbz3n6x5gi"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-deep" ,perl-test-deep)
       ("perl-test-exception" ,perl-test-exception)))
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-moose" ,perl-moose)
       ("perl-moosex-emulate-class-accessor-fast"
        ,perl-moosex-emulate-class-accessor-fast)
       ("perl-namespace-clean" ,perl-namespace-clean)
       ("perl-object-signature" ,perl-object-signature)
       ("perl-test-www-mechanize-psgi" ,perl-test-www-mechanize-psgi)))
    (home-page "http://search.cpan.org/dist/Catalyst-Plugin-Session")
    (synopsis "Catalyst generic session plugin")
    (description "This plugin links the two pieces required for session
management in web applications together: the state, and the store.")
    (license (package-license perl))))

(define-public perl-catalyst-plugin-session-state-cookie
  (package
    (name "perl-catalyst-plugin-session-state-cookie")
    (version "0.17")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/M/MS/MSTROUT/"
                           "Catalyst-Plugin-Session-State-Cookie-"
                           version ".tar.gz"))
       (sha256
        (base32
         "1rvxbfnpf9x2pc2zgpazlcgdlr2dijmxgmcs0m5nazs0w6xikssb"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-catalyst-plugin-session" ,perl-catalyst-plugin-session)
       ("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-moose" ,perl-moose)
       ("perl-mro-compat" ,perl-mro-compat)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)))
    (home-page
     "http://search.cpan.org/dist/Catalyst-Plugin-Session-State-Cookie")
    (synopsis "Maintain session IDs using cookies")
    (description "In order for Catalyst::Plugin::Session to work, the session
ID needs to be stored on the client, and the session data needs to be stored
on the server.  This plugin stores the session ID on the client using the
cookie mechanism.")
    (license (package-license perl))))

(define-public perl-catalyst-plugin-session-store-fastmmap
  (package
    (name "perl-catalyst-plugin-session-store-fastmmap")
    (version "0.16")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/B/BO/BOBTFISH/"
                           "Catalyst-Plugin-Session-Store-FastMmap-"
                           version ".tar.gz"))
       (sha256
        (base32
         "0x3j6zv3wr41jlwr6yb2jpmcx019ibyn11y8653ffnwhpzbpzsxs"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-cache-fastmmap" ,perl-cache-fastmmap)
       ("perl-catalyst-plugin-session" ,perl-catalyst-plugin-session)
       ("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-moosex-emulate-class-accessor-fast"
        ,perl-moosex-emulate-class-accessor-fast)
       ("perl-mro-compat" ,perl-mro-compat)
       ("perl-path-class" ,perl-path-class)))
    (home-page
     "http://search.cpan.org/dist/Catalyst-Plugin-Session-Store-FastMmap")
    (synopsis "FastMmap session storage backend")
    (description "Catalyst::Plugin::Session::Store::FastMmap is a fast session
storage plugin for Catalyst that uses an mmap'ed file to act as a shared
memory interprocess cache.  It is based on Cache::FastMmap.")
    (license (package-license perl))))

(define-public perl-catalyst-plugin-stacktrace
  (package
    (name "perl-catalyst-plugin-stacktrace")
    (version "0.12")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/B/BO/BOBTFISH/"
                           "Catalyst-Plugin-StackTrace-" version ".tar.gz"))
       (sha256
        (base32
         "1b2ksz74cpigxqzf63rddar3vfmnbpwpdcbs11v0ml89pb8ar79j"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-devel-stacktrace" ,perl-devel-stacktrace)
       ("perl-mro-compat" ,perl-mro-compat)))
    (home-page "http://search.cpan.org/dist/Catalyst-Plugin-StackTrace")
    (synopsis "Stack trace on the Catalyst debug screen")
    (description "This plugin enhances the standard Catalyst debug screen by
including a stack trace of your application up to the point where the error
occurred.  Each stack frame is displayed along with the package name, line
number, file name, and code context surrounding the line number.")
    (license (package-license perl))))

(define-public perl-catalyst-plugin-static-simple
  (package
    (name "perl-catalyst-plugin-static-simple")
    (version "0.33")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/J/JJ/JJNAPIORK/"
                           "Catalyst-Plugin-Static-Simple-" version ".tar.gz"))
       (sha256
        (base32
         "1h8f12bhzh0ssq9gs8r9g3hqn8zn2k0q944vc1vm8j81bns16msy"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-mime-types" ,perl-mime-types)
       ("perl-moose" ,perl-moose)
       ("perl-moosex-types" ,perl-moosex-types)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)))
    (home-page "http://search.cpan.org/dist/Catalyst-Plugin-Static-Simple")
    (synopsis "Simple serving of static pages")
    (description "The Static::Simple plugin is designed to make serving static
content in your application during development quick and easy, without
requiring a single line of code from you.  This plugin detects static files by
looking at the file extension in the URL (such as .css or .png or .js).  The
plugin uses the lightweight MIME::Types module to map file extensions to
IANA-registered MIME types, and will serve your static files with the correct
MIME type directly to the browser, without being processed through Catalyst.")
    (license (package-license perl))))

(define-public perl-catalyst-runtime
  (package
    (name "perl-catalyst-runtime")
    (version "5.90082")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/J/JJ/JJNAPIORK/"
                           "Catalyst-Runtime-" version ".tar.gz"))
       (sha256
        (base32
         "1gs70nq4rikpq6siwds9disb1z03vwjzf979xi9kf7saa1drfncs"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-fatal" ,perl-test-fatal)))
    (propagated-inputs
     `(("perl-cgi-simple" ,perl-cgi-simple)
       ("perl-cgi-struct" ,perl-cgi-struct)
       ("perl-class-c3-adopt-next" ,perl-class-c3-adopt-next)
       ("perl-class-data-inheritable" ,perl-class-data-inheritable)
       ("perl-class-date" ,perl-class-date)
       ("perl-class-load" ,perl-class-load)
       ("perl-data-dump" ,perl-data-dump)
       ("perl-http-body" ,perl-http-body)
       ("perl-http-message" ,perl-http-message)
       ("perl-http-request-ascgi" ,perl-http-request-ascgi)
       ("perl-io-stringy" ,perl-io-stringy)
       ("perl-json-maybexs" ,perl-json-maybexs)
       ("perl-libwww" ,perl-libwww)
       ("perl-moose" ,perl-moose)
       ("perl-moosex-emulate-class-accessor-fast"
        ,perl-moosex-emulate-class-accessor-fast)
       ("perl-moosex-getopt" ,perl-moosex-getopt)
       ("perl-moosex-methodattributes" ,perl-moosex-methodattributes)
       ("perl-moosex-role-withoverloading" ,perl-moosex-role-withoverloading)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)
       ("perl-namespace-clean" ,perl-namespace-clean)
       ("perl-path-class" ,perl-path-class)
       ("perl-plack" ,perl-plack)
       ("perl-plack-middleware-fixmissingbodyinredirect"
        ,perl-plack-middleware-fixmissingbodyinredirect)
       ("perl-plack-middleware-methodoverride"
        ,perl-plack-middleware-methodoverride)
       ("perl-plack-middleware-removeredundantbody"
        ,perl-plack-middleware-removeredundantbody)
       ("perl-plack-middleware-reverseproxy"
        ,perl-plack-middleware-reverseproxy)
       ("perl-plack-test-externalserver" ,perl-plack-test-externalserver)
       ("perl-safe-isa" ,perl-safe-isa)
       ("perl-string-rewriteprefix" ,perl-string-rewriteprefix)
       ("perl-text-simpletable" ,perl-text-simpletable)
       ("perl-tree-simple" ,perl-tree-simple)
       ("perl-tree-simple-visitorfactory" ,perl-tree-simple-visitorfactory)
       ("perl-try-tiny" ,perl-try-tiny)
       ("perl-uri" ,perl-uri)
       ("perl-uri-ws" ,perl-uri-ws)))
    (home-page "http://search.cpan.org/dist/Catalyst-Runtime")
    (synopsis "The Catalyst Framework Runtime")
    (description "Catalyst is a modern framework for making web applications.
It is designed to make it easy to manage the various tasks you need to do to
run an application on the web, either by doing them itself, or by letting you
\"plug in\" existing Perl modules that do what you need.")
    (license (package-license perl))))

(define-public perl-catalyst-traitfor-request-proxybase
  (package
    (name "perl-catalyst-traitfor-request-proxybase")
    (version "0.000005")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/B/BO/BOBTFISH/"
                           "Catalyst-TraitFor-Request-ProxyBase-"
                           version ".tar.gz"))
       (sha256
        (base32
         "02kir63d5cs2ipj3fn1qlmmx3gqi1xqzrxfr4pv5vjhjgsm0zgx7"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-catalystx-roleapplicator" ,perl-catalystx-roleapplicator)
       ("perl-http-message" ,perl-http-message)))
    (propagated-inputs
     `(("perl-moose" ,perl-moose)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)
       ("perl-uri" ,perl-uri)))
    (home-page
     "http://search.cpan.org/dist/Catalyst-TraitFor-Request-ProxyBase")
    (synopsis "Replace request base with value passed by HTTP proxy")
    (description "This module is a Moose::Role which allows you more
flexibility in your application's deployment configurations when deployed
behind a proxy.  Using this module, the request base ($c->req->base) is
replaced with the contents of the X-Request-Base header.")
    (license (package-license perl))))

(define-public perl-catalyst-view-download
  (package
    (name "perl-catalyst-view-download")
    (version "0.09")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/G/GA/GAUDEON/"
                           "Catalyst-View-Download-" version ".tar.gz"))
       (sha256
        (base32
         "1qgq6y9iwfbhbkbgpw9czang2ami6z8jk1zlagrzdisy4igqzkvs"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-test-simple" ,perl-test-simple)
       ("perl-test-www-mechanize-catalyst" ,perl-test-www-mechanize-catalyst)
       ("perl-text-csv" ,perl-text-csv)
       ("perl-xml-simple" ,perl-xml-simple)))
    (home-page "http://search.cpan.org/dist/Catalyst-View-Download")
    (synopsis "Download data in many formats")
    (description "The purpose of this module is to provide a method for
downloading data into many supportable formats.  For example, downloading a
table based report in a variety of formats (CSV, HTML, etc.).")
    (license (package-license perl))))

(define-public perl-catalyst-view-json
  (package
    (name "perl-catalyst-view-json")
    (version "0.35")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/J/JJ/JJNAPIORK/"
                           "Catalyst-View-JSON-" version ".tar.gz"))
       (sha256
        (base32
         "184pyghlrkl7p387bnyvswi2d9myvdg4v3lax6xrd59shskvpmkm"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-yaml" ,perl-yaml)))
    (inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-json-maybexs" ,perl-json-maybexs)
       ("perl-mro-compat" ,perl-mro-compat)))
    (home-page "http://search.cpan.org/dist/Catalyst-View-JSON")
    (synopsis "Catalyst JSON view")
    (description "Catalyst::View::JSON is a Catalyst View handler that returns
stash data in JSON format.")
    (license (package-license perl))))

(define-public perl-catalyst-view-tt
  (package
    (name "perl-catalyst-view-tt")
    (version "0.42")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/J/JJ/JJNAPIORK/"
                           "Catalyst-View-TT-" version ".tar.gz"))
     (sha256
      (base32
       "18ciik9fqaqjfasa9wicbjrsl3gjhjc15xzaj3rif57an25cl178"))))
  (build-system perl-build-system)
  (propagated-inputs
   `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
     ("perl-class-accessor" ,perl-class-accessor)
     ("perl-mro-compat" ,perl-mro-compat)
     ("perl-path-class" ,perl-path-class)
     ("perl-template-timer" ,perl-template-timer)
     ("perl-template-toolkit" ,perl-template-toolkit)))
  (home-page "http://search.cpan.org/dist/Catalyst-View-TT")
  (synopsis "Template View Class")
  (description "This module is a Catalyst view class for the Template
Toolkit.")
  (license (package-license perl))))

(define-public perl-catalystx-component-traits
  (package
    (name "perl-catalystx-component-traits")
    (version "0.19")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/R/RK/RKITOVER/"
                           "CatalystX-Component-Traits-" version ".tar.gz"))
       (sha256
        (base32
         "0iq4ci8m6g2c4g01fvdl568y7pjz28f3widk986v3pyhr7ll8j88"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-moose" ,perl-moose)
       ("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-moosex-methodattributes" ,perl-moosex-methodattributes)))
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-class-load" ,perl-class-load)
       ("perl-moose" ,perl-moose)
       ("perl-moosex-traits-pluggable" ,perl-moosex-traits-pluggable)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)
       ("perl-list-moreutils" ,perl-list-moreutils)))
    (home-page "http://search.cpan.org/dist/CatalystX-Component-Traits")
    (synopsis "Trait Loading and Resolution for Catalyst Components")
    (description "Adds a \"COMPONENT\" in Catalyst::Component method to your
Catalyst component base class that reads the optional \"traits\" parameter
from app and component config and instantiates the component subclass with
those traits using \"new_with_traits\" in MooseX::Traits from
MooseX::Traits::Pluggable.")
    (license (package-license perl))))

(define-public perl-catalystx-roleapplicator
  (package
    (name "perl-catalystx-roleapplicator")
    (version "0.005")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/H/HD/HDP/"
                           "CatalystX-RoleApplicator-" version ".tar.gz"))
       (sha256
        (base32
         "0vwaapxn8g5hs2xp63c4dwv9jmapmji4272fakssvgc9frklg3p2"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-moose" ,perl-moose)
       ("perl-moosex-relatedclassroles" ,perl-moosex-relatedclassroles)))
    (home-page "http://search.cpan.org/dist/CatalystX-RoleApplicator")
    (synopsis "Apply roles to Catalyst classes")
    (description "CatalystX::RoleApplicator applies roles to Catalyst
application classes.")
    (license (package-license perl))))

(define-public perl-catalystx-script-server-starman
  (package
    (name "perl-catalystx-script-server-starman")
    (version "0.02")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/A/AB/ABRAXXA/"
                           "CatalystX-Script-Server-Starman-"
                           version ".tar.gz"))
       (sha256
        (base32
         "0h02mpkc4cmi3jpvcd7iw7xyzx55bqvvl1qkf967gqkvpklm0qx5"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-www-mechanize-catalyst" ,perl-test-www-mechanize-catalyst)))
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-moose" ,perl-moose)
       ("perl-namespace-autoclean" ,perl-namespace-autoclean)
       ("starman" ,starman)))
    (home-page "http://search.cpan.org/dist/CatalystX-Script-Server-Starman")
    (synopsis "Catalyst development server with Starman")
    (description "This module provides a Catalyst extension to replace the
development server with Starman.")
    (license (package-license perl))))

(define-public perl-cgi-simple
  (package
    (name "perl-cgi-simple")
    (version "1.115")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/S/SZ/SZABGAB/"
                           "CGI-Simple-" version ".tar.gz"))
       (sha256
        (base32
         "1nkyb1m1g5r47xykflf68dplanih5p15njv82frbgbsms34kp1sg"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-io-stringy" ,perl-io-stringy))) ;for IO::Scalar
    (home-page "http://search.cpan.org/dist/CGI-Simple")
    (synopsis "CGI interface that is CGI.pm compliant")
    (description "CGI::Simple provides a relatively lightweight drop in
replacement for CGI.pm.  It shares an identical OO interface to CGI.pm for
parameter parsing, file upload, cookie handling and header generation.")
    (license (package-license perl))))

(define-public perl-cgi-struct
  (package
    (name "perl-cgi-struct")
    (version "1.21")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/F/FU/FULLERMD/"
                           "CGI-Struct-" version ".tar.gz"))
       (sha256
        (base32
         "0v4xq2qpryr7i6jngw1wpn8yr2kiib10yxp4aih90vfdznkqsgfi"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-deep" ,perl-test-deep)))
    (home-page "http://search.cpan.org/dist/CGI-Struct")
    (synopsis "Build structures from CGI data")
    (description "This is a module for building structured data from CGI
inputs, in a manner reminiscent of how PHP does.")
    (license l:bsd-2)))

(define-public perl-datetime-format-http
  (package
    (name "perl-datetime-format-http")
    (version "0.42")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/C/CK/CKRAS/"
                           "DateTime-Format-HTTP-" version ".tar.gz"))
       (sha256
        (base32
         "0h6qqdg1yzqkdxp7hqlp0qa7d1y64nilgimxs79dys2ryjfpcknh"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-datetime" ,perl-datetime)
       ("perl-http-date" ,perl-http-date)))
    (home-page "http://search.cpan.org/dist/DateTime-Format-HTTP")
    (synopsis "Date conversion routines")
    (description "This module provides functions that deal with the date
formats used by the HTTP protocol.")
    (license (package-license perl))))

(define-public perl-digest-md5-file
  (package
    (name "perl-digest-md5-file")
    (version "0.08")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/D/DM/DMUEY/"
                           "Digest-MD5-File-" version ".tar.gz"))
       (sha256
        (base32
         "060jzf45dlwysw5wsm7av1wvpl06xgk415kwwpvv89r6wda3md5d"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-libwww" ,perl-libwww)))
    (home-page "http://search.cpan.org/dist/Digest-MD5-File")
    (synopsis "MD5 sums for files and urls")
    (description "Digest::MD5::File is a Perl extension for getting MD5 sums
for files and urls.")
    (license (package-license perl))))

(define-public perl-encode-locale
  (package
    (name "perl-encode-locale")
    (version "1.03")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/Encode-Locale-"
                   version ".tar.gz"))
             (sha256
              (base32
               "0m9d1vdphlyzybgmdanipwd9ndfvyjgk3hzw250r299jjgh3fqzp"))))
    (build-system perl-build-system)
    (license (package-license perl))
    (synopsis "Perl locale encoding determination")
    (description
     "The POSIX locale system is used to specify both the language
conventions requested by the user and the preferred character set to
consume and output.  The Encode::Locale module looks up the charset and
encoding (called a CODESET in the locale jargon) and arranges for the
Encode module to know this encoding under the name \"locale\".  It means
bytes obtained from the environment can be converted to Unicode strings
by calling Encode::encode(locale => $bytes) and converted back again
with Encode::decode(locale => $string).")
    (home-page "http://search.cpan.org/~gaas/Encode-Locale/")))

(define-public perl-file-listing
  (package
    (name "perl-file-listing")
    (version "6.04")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/File-Listing-"
                   version ".tar.gz"))
             (sha256
              (base32
               "1xcwjlnxaiwwpn41a5yi6nz95ywh3szq5chdxiwj36kqsvy5000y"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-http-date" ,perl-http-date)))
    (license (package-license perl))
    (synopsis "Perl directory listing parser")
    (description
     "The File::Listing module exports a single function called parse_dir(),
which can be used to parse directory listings.")
    (home-page "http://search.cpan.org/~gaas/File-Listing/")))

(define-public perl-finance-quote
  (package
   (name "perl-finance-quote")
   (version "1.37")
   (source
    (origin
      (method url-fetch)
      (uri (string-append "https://cpan.metacpan.org/authors/id/E/EC/ECOCODE/"
                          "Finance-Quote-" version ".tar.gz"))
      (sha256
       (base32
        "1b6pbh7f76fb5sa4f0lhx085xy55pprz5v7z7li7pqiyw7i4f4bf"))
      (patches (list
                (search-patch "perl-finance-quote-unuse-mozilla-ca.patch")))))
   (build-system perl-build-system)
   (propagated-inputs
    `(("perl-datetime" ,perl-datetime)
      ("perl-html-parser" ,perl-html-parser)
      ("perl-html-tableextract" ,perl-html-tableextract)
      ("perl-html-tree" ,perl-html-tree)
      ("perl-http-cookies" ,perl-http-cookies)
      ("perl-http-message" ,perl-http-message)
      ("perl-json" ,perl-json)
      ("perl-libwww" ,perl-libwww)
      ("perl-lwp-protocol-https" ,perl-lwp-protocol-https)
      ("perl-uri" ,perl-uri)))
   (home-page "http://search.cpan.org/dist/Finance-Quote")
   (synopsis "Stock and mutual fund quotes")
   (description
    "Finance::Quote gets stock quotes from various internet sources, including
Yahoo! Finance, Fidelity Investments, and the Australian Stock Exchange.")
   (license l:gpl2)))

(define-public perl-gssapi
  (package
    (name "perl-gssapi")
    (version "0.28")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/A/AG/AGROLMS/"
                           "GSSAPI-" version ".tar.gz"))
       (sha256
        (base32
         "1mkhwxjjlhr58pd770i9gnf7zy7jj092iv6jfbnb8bvnc5xjr3vx"))))
    (build-system perl-build-system)
    (inputs `(("gssapi" ,mit-krb5)))
    (arguments
     `(#:make-maker-flags
       `(,(string-append "--gssapiimpl=" (assoc-ref %build-inputs "gssapi")))))
    (home-page "http://search.cpan.org/dist/GSSAPI")
    (synopsis "Perl extension providing access to the GSSAPIv2 library")
    (description "This is a Perl extension for using GSSAPI C bindings as
described in RFC 2744.")
    (license (package-license perl))))

(define-public perl-html-element-extended
  (package
    (name "perl-html-element-extended")
    (version "1.18")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/M/MS/MSISK/"
                           "HTML-Element-Extended-" version ".tar.gz"))
       (sha256
        (base32
         "0axknss8c368r5i082yhkfj8mq0w4nglfrpcxcayyzzj13qimvzk"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-html-tree" ,perl-html-tree)))
    (home-page "http://search.cpan.org/dist/HTML-Element-Extended")
    (synopsis "Manipulate tables of HTML::Element")
    (description
     "HTML::Element::Extended is a Perl extension for manipulating a table
composed of HTML::Element style components.")
    (license (package-license perl))))

(define-public perl-html-form
  (package
    (name "perl-html-form")
    (version "6.03")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/G/GA/GAAS/"
                           "HTML-Form-" version ".tar.gz"))
       (sha256
        (base32
         "0dpwr7yz6hjc3bcqgcbdzjjk9l58ycdjmbam9nfcmm85y2a1vh38"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-html-parser" ,perl-html-parser)
       ("perl-html-tagset" ,perl-html-tagset)
       ("perl-http-message" ,perl-http-message)
       ("perl-lwp-mediatypes" ,perl-lwp-mediatypes)
       ("perl-uri" ,perl-uri)))
    (home-page "http://search.cpan.org/dist/HTML-Form")
    (synopsis "Perl class representing an HTML form element")
    (description "Objects of the HTML::Form class represents a single HTML
<form> ... </form> instance.")
    (license (package-license perl))))

(define-public perl-html-lint
  (package
    (name "perl-html-lint")
    (version "2.20")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/P/PE/PETDANCE/"
                           "HTML-Lint-" version ".tar.gz"))
       (sha256
        (base32
         "15vrqjnlb0f8rib1kqdf4islqy6i33h08wy7b1bkgd550p7lfjwk"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-html-parser" ,perl-html-parser)
       ("perl-html-tagset" ,perl-html-tagset)
       ("perl-libwww" ,perl-libwww)))
    (home-page "http://search.cpan.org/dist/HTML-Lint")
    (synopsis "Check for HTML errors in a string or file")
    (description "HTML::Lint is a pure-Perl HTML parser and checker for
syntactic legitmacy.")
    (license l:artistic2.0)))

(define-public perl-html-tableextract
  (package
    (name "perl-html-tableextract")
    (version "2.13")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://cpan.metacpan.org/authors/id/M/MS/MSISK/"
                           "HTML-TableExtract-" version ".tar.gz"))
       (sha256
        (base32
         "01jimmss3q68a89696wmclvqwb2ybz6xgabpnbp6mm6jcni82z8a"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-html-element-extended" ,perl-html-element-extended)
       ("perl-html-parser" ,perl-html-parser)))
    (home-page "http://search.cpan.org/dist/HTML-TableExtract")
    (synopsis "Extract contents from HTML tables")
    (description
     "HTML::TableExtract is a Perl module for extracting the content contained
in tables within an HTML document, either as text or encoded element trees.")
    (license (package-license perl))))

(define-public perl-html-tree
  (package
    (name "perl-html-tree")
    (version "5.03")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/C/CJ/CJM/"
                           "HTML-Tree-" version ".tar.gz"))
       (sha256
        (base32
         "13qlqbpixw470gnck0xgny8hyjj576m8y24bba2p9ai2lvy76vbx"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-fatal" ,perl-test-fatal)))
    (propagated-inputs
     `(("perl-html-parser" ,perl-html-parser)
       ("perl-html-tagset" ,perl-html-tagset)
       ("perl-libwww" ,perl-libwww)))
    (home-page "http://search.cpan.org/dist/HTML-Tree")
    (synopsis "Work with HTML in a DOM-like tree structure")
    (description "This distribution contains a suite of modules for
representing, creating, and extracting information from HTML syntax trees.")
    (license (package-license perl))))

(define-public perl-html-parser
  (package
    (name "perl-html-parser")
    (version "3.71")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/HTML-Parser-"
                   version ".tar.gz"))
             (sha256
              (base32
               "00nqzdgl7c3jilx7mil19k5jwcw3as14pvkjgxi97zyk94vqp4dy"))))
    (build-system perl-build-system)
    (inputs
     `(("perl-html-tagset" ,perl-html-tagset)))
    (license (package-license perl))
    (synopsis "Perl HTML parser class")
    (description
     "Objects of the HTML::Parser class will recognize markup and separate
it from plain text (alias data content) in HTML documents.  As different
kinds of markup and text are recognized, the corresponding event handlers
are invoked.")
    (home-page "http://search.cpan.org/~gaas/HTML-Parser/")))

(define-public perl-html-tagset
  (package
    (name "perl-html-tagset")
    (version "3.20")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/P/PE/PETDANCE/HTML-Tagset-"
                   version ".tar.gz"))
             (sha256
              (base32
               "1qh8249wgr4v9vgghq77zh1d2zs176bir223a8gh3k9nksn7vcdd"))))
    (build-system perl-build-system)
    (license (package-license perl))
    (synopsis "Perl data tables useful in parsing HTML")
    (description
     "The HTML::Tagset module contains several data tables useful in various
kinds of HTML parsing operations.")
    (home-page "http://search.cpan.org/dist/HTML-Tagset/")))

(define-public perl-html-template
  (package
    (name "perl-html-template")
    (version "2.95")
    (source (origin
              (method url-fetch)
              (uri (string-append "mirror://cpan/authors/id/W/WO/WONKO/"
                                  "HTML-Template-" version ".tar.gz"))
              (sha256
               (base32
                "07ahpfgidxsw2yb7y8i7bbr8s64aq6qgq832h9jswmksxbd0l43q"))))
    (build-system perl-build-system)
    (home-page "http://search.cpan.org/dist/HTML-Template")
    (synopsis "HTML-like templates")
    (description
     "This module attempts to make using HTML templates simple and natural.
It extends standard HTML with a few new HTML-esque tags: @code{<TMPL_VAR>},
@code{<TMPL_LOOP>}, @code{<TMPL_INCLUDE>}, @code{<TMPL_IF>},
@code{<TMPL_ELSE>} and @code{<TMPL_UNLESS>}.  The file written with HTML and
these new tags is called a template.  Using this module you fill in the values
for the variables, loops and branches declared in the template.  This allows
you to separate design from the data.")
    (license (package-license perl))))

(define-public perl-http-body
  (package
    (name "perl-http-body")
    (version "1.19")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/G/GE/GETTY/"
                           "HTTP-Body-" version ".tar.gz"))
       (sha256
        (base32
         "0ahhksj0zg6wq6glpjkxdr3byd5riwvq2f5aw21n1jcsl71nll01"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-deep" ,perl-test-deep)))
    (propagated-inputs
     `(("perl-file-temp" ,perl-file-temp)
       ("perl-http-message" ,perl-http-message))) ;For HTTP::Headers
    (home-page "http://search.cpan.org/dist/HTTP-Body")
    (synopsis "HTTP Body Parser")
    (description "HTTP::Body parses chunks of HTTP POST data and supports
application/octet-stream, application/json, application/x-www-form-urlencoded,
and multipart/form-data.")
    (license (package-license perl))))

(define-public perl-http-cookiejar
  (package
    (name "perl-http-cookiejar")
    (version "0.006")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/D/DA/DAGOLDEN/"
                           "HTTP-CookieJar-" version ".tar.gz"))
       (sha256
        (base32
         "0c7l29ak6ba2j006ca00vnkxpyc1fvpikydjvsb24s50zf1mv7b2"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-deep" ,perl-test-deep)
       ("perl-test-requires" ,perl-test-requires)
       ("perl-time-mock" ,perl-time-mock)))
    (inputs
     `(("perl-time-local" ,perl-time-local)
       ("perl-http-date" ,perl-http-date)))
    (home-page "http://search.cpan.org/dist/HTTP-CookieJar")
    (synopsis "Minimalist HTTP user agent cookie jar")
    (description "This module implements a minimalist HTTP user agent cookie
jar in conformance with RFC 6265 <http://tools.ietf.org/html/rfc6265>.")
    (license l:asl2.0)))

(define-public perl-http-cookies
  (package
    (name "perl-http-cookies")
    (version "6.01")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/HTTP-Cookies-"
                   version ".tar.gz"))
             (sha256
              (base32
               "087bqmg22dg3vj7gssh3pcsh9y1scimkbl5h1kc8jqyfhgisvlzm"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-http-message" ,perl-http-message)))
    (license (package-license perl))
    (synopsis "Perl HTTP cookie jars")
    (description
     "The HTTP::Cookies class is for objects that represent a cookie jar,
that is, a database of all the HTTP cookies that a given LWP::UserAgent
object knows about.")
    (home-page "http://search.cpan.org/~gaas/HTTP-Cookies/")))

(define-public perl-http-daemon
  (package
    (name "perl-http-daemon")
    (version "6.01")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/HTTP-Daemon-"
                   version ".tar.gz"))
             (sha256
              (base32
               "1hmd2isrkilf0q0nkxms1q64kikjmcw9imbvrjgky6kh89vqdza3"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-http-message" ,perl-http-message)
       ("perl-lwp-mediatypes" ,perl-lwp-mediatypes)))
    (license (package-license perl))
    (synopsis "Perl simple http server class")
    (description
     "Instances of the HTTP::Daemon class are HTTP/1.1 servers that listen
on a socket for incoming requests.  The HTTP::Daemon is a subclass of
IO::Socket::INET, so you can perform socket operations directly on it too.")
    (home-page "http://search.cpan.org/~gaas/HTTP-Daemon/")))

(define-public perl-http-date
  (package
    (name "perl-http-date")
    (version "6.02")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/HTTP-Date-"
                   version ".tar.gz"))
             (sha256
              (base32
               "0cz357kafhhzw7w59iyi0wvhw7rlh5g1lh38230ckw7rl0fr9fg8"))))
    (build-system perl-build-system)
    (license (package-license perl))
    (synopsis "Perl date conversion routines")
    (description
     "The HTTP::Date module provides functions that deal with date formats
used by the HTTP protocol (and then some more).")
    (home-page "http://search.cpan.org/~gaas/HTTP-Date/")))

(define-public perl-http-message
  (package
    (name "perl-http-message")
    (version "6.06")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/HTTP-Message-"
                   version ".tar.gz"))
             (sha256
              (base32
               "0qxdrcak97azjvqyx1anpb2ky6vp6vc37x0wcfjdqfajkh09fzh8"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-http-date" ,perl-http-date)
       ("perl-io-html" ,perl-io-html)
       ("perl-lwp-mediatypes" ,perl-lwp-mediatypes)
       ("perl-uri" ,perl-uri)))
    (license (package-license perl))
    (synopsis "Perl HTTP style message")
    (description
     "An HTTP::Message object contains some headers and a content body.")
    (home-page "http://search.cpan.org/~gaas/HTTP-Message/")))

(define-public perl-http-negotiate
  (package
    (name "perl-http-negotiate")
    (version "6.01")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/HTTP-Negotiate-"
                   version ".tar.gz"))
             (sha256
              (base32
               "05p053vjs5g91v5cmjnny7a3xzddz5k7vnjw81wfh01ilqg9qwhw"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-http-message" ,perl-http-message)))
    (license (package-license perl))
    (synopsis "Perl http content negotiation")
    (description
     "The HTTP::Negotiate module provides a complete implementation of the
HTTP content negotiation algorithm specified in
draft-ietf-http-v11-spec-00.ps chapter 12.  Content negotiation allows for
the selection of a preferred content representation based upon attributes
of the negotiable variants and the value of the various Accept* header
fields in the request.")
    (home-page "http://search.cpan.org/~gaas/HTTP-Negotiate/")))

(define-public perl-http-parser
  (package
    (name "perl-http-parser")
    (version "0.06")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/E/ED/EDECA/"
                           "HTTP-Parser-" version ".tar.gz"))
       (sha256
        (base32
         "0idwq3jk595xil65lmxz128ha7s3r2n5zknisddpgwnqrghs3igq"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-http-message" ,perl-http-message)
       ("perl-uri" ,perl-uri)))
    (home-page "http://search.cpan.org/dist/HTTP-Parser")
    (synopsis "Parse HTTP/1.1 requests")
    (description "This is an HTTP request parser.  It takes chunks of text as
received and returns a 'hint' as to what is required, or returns the
HTTP::Request when a complete request has been read.  HTTP/1.1 chunking is
supported.")
    (license (package-license perl))))

(define-public perl-http-parser-xs
  (package
    (name "perl-http-parser-xs")
    (version "0.17")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/K/KA/KAZUHO/"
                           "HTTP-Parser-XS-" version ".tar.gz"))
       (sha256
        (base32
         "02d84xq1mm53c7jl33qyb7v5w4372vydp74z6qj0vc96wcrnhkkr"))))
    (build-system perl-build-system)
    (home-page "http://search.cpan.org/dist/HTTP-Parser-XS")
    (synopsis "Fast HTTP request parser")
    (description "HTTP::Parser::XS is a fast, primitive HTTP request/response
parser.")
    (license (package-license perl))))

(define-public perl-http-request-ascgi
  (package
    (name "perl-http-request-ascgi")
    (version "1.2")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/F/FL/FLORA/"
                           "HTTP-Request-AsCGI-" version ".tar.gz"))
       (sha256
        (base32
         "1smwmiarwcgq7vjdblnb6ldi2x1s5sk5p15p7xvm5byiqq3znnwl"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-class-accessor" ,perl-class-accessor)
       ("perl-http-message" ,perl-http-message)))
    (home-page "http://search.cpan.org/dist/HTTP-Request-AsCGI")
    (synopsis "Set up a CGI environment from an HTTP::Request")
    (description "This module provides a convenient way to set up a CGI
environment from an HTTP::Request.")
    (license (package-license perl))))

(define-public perl-http-server-simple
  (package
    (name "perl-http-server-simple")
    (version "0.44")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/J/JE/JESSE/"
                           "HTTP-Server-Simple-" version ".tar.gz"))
       (sha256
        (base32
         "05klpfkss2a6i5ihmvcm27fyar0f2v4ispg2f49agab3va1gix6g"))))
    (build-system perl-build-system)
    (arguments
     ;; See the discussion of a related tests issue at
     ;; https://lists.gnu.org/archive/html/guix-devel/2015-01/msg00346.html
     `(#:tests? #f))
    (home-page "http://search.cpan.org/dist/HTTP-Server-Simple")
    (synopsis "Lightweight HTTP server")
    (description "HTTP::Server::Simple is a simple standalone HTTP daemon with
no non-core module dependencies.  It can be used for building a standalone
http-based UI to your existing tools.")
    (license (package-license perl))))

(define-public perl-http-tiny
  (package
    (name "perl-http-tiny")
    (version "0.053")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/D/DA/DAGOLDEN/"
                           "HTTP-Tiny-" version ".tar.gz"))
       (sha256
        (base32
         "1bwy31xrcz5zfx1n3vc50vj1aqvzn5ccr7lgacl8wmi03a6w2af2"))))
    (build-system perl-build-system)
    (inputs
     `(("perl-http-cookiejar" ,perl-http-cookiejar)
       ("perl-io-socket-ip" ,perl-io-socket-ip)
       ("perl-io-socket-ssl" ,perl-io-socket-ssl)
       ("perl-net-ssleay" ,perl-net-ssleay)))
    (home-page "http://search.cpan.org/dist/HTTP-Tiny")
    (synopsis "HTTP/1.1 client")
    (description "This is a very simple HTTP/1.1 client, designed for doing
simple requests without the overhead of a large framework like LWP::UserAgent.
It supports proxies and redirection.  It also correctly resumes after EINTR.")
    (license (package-license perl))))

(define-public perl-io-html
  (package
    (name "perl-io-html")
    (version "1.00")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/C/CJ/CJM/IO-HTML-"
                   version ".tar.gz"))
             (sha256
              (base32
               "06nj3a0xgp5jxwxx6ayglfk2v7npf5a7gwkqsjlkapjkybarzqh4"))))
    (build-system perl-build-system)
    (license (package-license perl))
    (synopsis "Perl module to open an HTML file with automatic charset detection")
    (description
     "IO::HTML provides an easy way to open a file containing HTML while
automatically determining its encoding.  It uses the HTML5 encoding sniffing
algorithm specified in section 8.2.2.1 of the draft standard.")
    (home-page "http://search.cpan.org/~cjm/IO-HTML/")))

(define-public perl-io-socket-ip
  (package
    (name "perl-io-socket-ip")
    (version "0.36")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/P/PE/PEVANS/"
                           "IO-Socket-IP-" version ".tar.gz"))
       (sha256
        (base32
         "0ky20hmln6waipzqikizyw04vpszf70fgpshz7ib8zv8480ri456"))))
    (build-system perl-build-system)
    (home-page "http://search.cpan.org/dist/IO-Socket-IP")
    (synopsis "Family-neutral IP socket supporting both IPv4 and IPv6")
    (description "This module provides a protocol-independent way to use IPv4
and IPv6 sockets, intended as a replacement for IO::Socket::INET.")
    (license (package-license perl))))

(define-public perl-io-socket-ssl
  (package
    (name "perl-io-socket-ssl")
    (version "2.002")
    (source (origin
              (method url-fetch)
              (uri (string-append "mirror://cpan/authors/id/S/SU/SULLR/"
                                  "IO-Socket-SSL-" version ".tar.gz"))
              (sha256
               (base32
                "1mph52lw6x5v44wf8mw00llzi8pp6k5c4jnrnrvlacrlfv260jb8"))))
    (build-system perl-build-system)
    (propagated-inputs `(("perl-net-ssleay" ,perl-net-ssleay)))
    (synopsis "Nearly transparent SSL encapsulation for IO::Socket::INET")
    (description
     "IO::Socket::SSL makes using SSL/TLS much easier by wrapping the
necessary functionality into the familiar IO::Socket interface and providing
secure defaults whenever possible.  This way existing applications can be made
SSL-aware without much effort, at least if you do blocking I/O and don't use
select or poll.")
    (license (package-license perl))
    (home-page "https://github.com/noxxi/p5-io-socket-ssl")))

(define-public perl-libwww
  (package
    (name "perl-libwww")
    (version "6.13")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/E/ET/ETHER/libwww-perl-"
                   version ".tar.gz"))
             (sha256
              (base32
               "1cpqjl59viw50bnbdyn8xzrwzg7g54b2rszw0fifacqrppp17gaz"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-encode-locale" ,perl-encode-locale)
       ("perl-file-listing" ,perl-file-listing)
       ("perl-html-parser" ,perl-html-parser)
       ("perl-http-cookies" ,perl-http-cookies)
       ("perl-http-daemon" ,perl-http-daemon)
       ("perl-http-negotiate" ,perl-http-negotiate)
       ("perl-net-http" ,perl-net-http)
       ("perl-www-robotrules" ,perl-www-robotrules)))
    (license (package-license perl))
    (synopsis "Perl modules for the WWW")
    (description
     "The libwww-perl collection is a set of Perl modules which provides a
simple and consistent application programming interface to the
World-Wide Web.  The main focus of the library is to provide classes
and functions that allow you to write WWW clients.  The library also
contains modules that are of more general use and even classes that
help you implement simple HTTP servers.")
    (home-page "http://search.cpan.org/dist/libwww-perl/")))

(define-public perl-lwp-mediatypes
  (package
    (name "perl-lwp-mediatypes")
    (version "6.02")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/LWP-MediaTypes-"
                   version ".tar.gz"))
             (sha256
              (base32
               "0xmnblp962qy02akah30sji8bxrqcyqlff2w95l199ghql60ny8q"))))
    (build-system perl-build-system)
    (license (package-license perl))
    (synopsis "Perl module to guess the media type for a file or a URL")
    (description
     "The LWP::MediaTypes module provides functions for handling media (also
known as MIME) types and encodings.  The mapping from file extensions to
media types is defined by the media.types file.  If the ~/.media.types file
exists it is used instead.")
    (home-page "http://search.cpan.org/~gaas/LWP-MediaTypes/")))

(define-public perl-lwp-protocol-https
  (package
    (name "perl-lwp-protocol-https")
    (version "6.06")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/M/MS/MSCHILLI/"
                           "LWP-Protocol-https-" version ".tar.gz"))
       (sha256
        (base32
         "1vxdjqj4bwq56m9h1bqqwkk3c6jr76f2zqzvwa26yjng3p686v5q"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-io-socket-ssl" ,perl-io-socket-ssl)
       ("perl-libwww" ,perl-libwww)
       ;; Users should instead make sure SSL_ca_path is set properly.
       ;; ("perl-mozilla-ca" ,perl-mozilla-ca)
       ("perl-net-http" ,perl-net-http)))
    (home-page "http://search.cpan.org/dist/LWP-Protocol-https")
    (synopsis "HTTPS support for LWP::UserAgent")
    (description "The LWP::Protocol::https module provides support for using
https schemed URLs with LWP.")
    (license (package-license perl))))

(define-public perl-lwp-useragent-determined
  (package
    (name "perl-lwp-useragent-determined")
    (version "1.07")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/A/AL/ALEXMV/"
                           "LWP-UserAgent-Determined-" version ".tar.gz"))
       (sha256
        (base32
         "0lyvbpjng7yfvyha9rp2y2c6liz5hhplmd2grc8jlsfkih7dbn06"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-libwww" ,perl-libwww)))
    (home-page "http://search.cpan.org/dist/LWP-UserAgent-Determined")
    (synopsis "Virtual browser that retries errors")
    (description "LWP::UserAgent::Determined works just like LWP::UserAgent,
except that when you use it to get a web page but run into a
possibly-temporary error (like a DNS lookup timeout), it'll wait a few seconds
and retry a few times.")
    (license (package-license perl))))

(define-public perl-net-amazon-s3
  (package
    (name "perl-net-amazon-s3")
    (version "0.60")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/P/PF/PFIG/"
                           "Net-Amazon-S3-" version ".tar.gz"))
       (sha256
        (base32
         "10dcsq4s2kc9cb1vccx17r187c81drirc3s1hbxh3rb8489kg2b2"))
       (patches (list
                 (search-patch "perl-net-amazon-s3-moose-warning.patch")))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-libwww" ,perl-libwww)
       ("perl-test-exception" ,perl-test-exception)))
    (propagated-inputs
     `(("perl-data-stream-bulk" ,perl-data-stream-bulk)
       ("perl-datetime-format-http" ,perl-datetime-format-http)
       ("perl-digest-hmac" ,perl-digest-hmac)
       ("perl-digest-md5-file" ,perl-digest-md5-file)
       ("perl-file-find-rule" ,perl-file-find-rule)
       ("perl-http-date" ,perl-http-date)
       ("perl-http-message" ,perl-http-message)
       ("perl-lwp-useragent-determined" ,perl-lwp-useragent-determined)
       ("perl-mime-types" ,perl-mime-types)
       ("perl-moose" ,perl-moose)
       ("perl-moosex-strictconstructor" ,perl-moosex-strictconstructor)
       ("perl-moosex-types-datetime-morecoercions"
        ,perl-moosex-types-datetime-morecoercions)
       ("perl-path-class" ,perl-path-class)
       ("perl-regexp-common" ,perl-regexp-common)
       ("perl-term-encoding" ,perl-term-encoding)
       ("perl-term-progressbar-simple" ,perl-term-progressbar-simple)
       ("perl-uri" ,perl-uri)
       ("perl-xml-libxml" ,perl-xml-libxml)))
    (home-page "http://search.cpan.org/dist/Net-Amazon-S3")
    (synopsis "Perl interface to Amazon S3")
    (description "This module provides a Perlish interface to Amazon S3.")
    (license (package-license perl))))

(define-public perl-net-http
  (package
    (name "perl-net-http")
    (version "6.07")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/M/MS/MSCHILLI/Net-HTTP-"
                   version ".tar.gz"))
             (sha256
              (base32
               "0r034hhci0yqbrkrh1gv6vi5g3i0kpd1k84z62nk02asb8rf0ccz"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-io-socket-ssl" ,perl-io-socket-ssl)
       ("perl-uri" ,perl-uri)))
    (license (package-license perl))
    (synopsis "Perl low-level HTTP connection (client)")
    (description
     "The Net::HTTP class is a low-level HTTP client.  An instance of the
Net::HTTP class represents a connection to an HTTP server.  The HTTP protocol
is described in RFC 2616.  The Net::HTTP class supports HTTP/1.0 and
HTTP/1.1.")
    (home-page "http://search.cpan.org/dist/Net-HTTP")))

(define-public perl-net-server
  (package
    (name "perl-net-server")
    (version "2.008")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/R/RH/RHANDOM/"
                           "Net-Server-" version ".tar.gz"))
       (sha256
        (base32
         "182gfikn7r40kmm3d35m2qc6r8g0y1j8gxbn9ffaawf8xmm0a889"))))
    (build-system perl-build-system)
    (home-page "http://search.cpan.org/dist/Net-Server")
    (synopsis "Extensible Perl server engine")
    (description "Net::Server is an extensible, generic Perl server engine.
It attempts to be a generic server as in Net::Daemon and NetServer::Generic.
It includes with it the ability to run as an inetd
process (Net::Server::INET), a single connection server (Net::Server or
Net::Server::Single), a forking server (Net::Server::Fork), a preforking
server which maintains a constant number of preforked
children (Net::Server::PreForkSimple), or as a managed preforking server which
maintains the number of children based on server load (Net::Server::PreFork).
In all but the inetd type, the server provides the ability to connect to one
or to multiple server ports.")
    (license (package-license perl))))

(define-public perl-net-smtp-ssl
  (package
    (name "perl-net-smtp-ssl")
    (version "1.03")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://cpan.metacpan.org/authors/id/R/RJ/RJBS/"
                           "Net-SMTP-SSL-" version ".tar.gz"))
       (sha256
	(base32
	 "05y94mb1vdw32mvwb0cp2h4ggh32f8j8nwwfjb8kjwxvfkfhyp9h"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-io-socket-ssl" ,perl-io-socket-ssl)))
    (home-page "http://search.cpan.org/dist/Net-SMTP-SSL")
    (synopsis "SSL support for Net::SMTP")
    (description "SSL support for Net::SMTP.")
    (license (package-license perl))))

(define-public perl-plack
  (package
    (name "perl-plack")
    (version "1.0033")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/M/MI/MIYAGAWA/"
                           "Plack-" version ".tar.gz"))
       (sha256
        (base32
         "081jg0xddzpg2anmqi9i6d7vs6c8z7k557bf8xl6vgb3h95pin5w"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-requires" ,perl-test-requires)
       ("perl-file-sharedir-install" ,perl-file-sharedir-install)))
    (propagated-inputs
     `(("perl-apache-logformat-compiler" ,perl-apache-logformat-compiler)
       ("perl-devel-stacktrace" ,perl-devel-stacktrace)
       ("perl-devel-stacktrace-ashtml" ,perl-devel-stacktrace-ashtml)
       ("perl-file-sharedir" ,perl-file-sharedir)
       ("perl-hash-multivalue" ,perl-hash-multivalue)
       ("perl-http-body" ,perl-http-body)
       ("perl-http-message" ,perl-http-message)
       ("perl-http-tiny" ,perl-http-tiny)
       ("perl-libwww" ,perl-libwww)
       ("perl-stream-buffered" ,perl-stream-buffered)
       ("perl-test-tcp" ,perl-test-tcp)
       ("perl-try-tiny" ,perl-try-tiny)
       ("perl-uri" ,perl-uri)))
    (home-page "http://search.cpan.org/dist/Plack")
    (synopsis "Perl Superglue for Web frameworks and servers (PSGI toolkit)")
    (description "Plack is a set of tools for using the PSGI stack.  It
contains middleware components, a reference server, and utilities for Web
application frameworks.  Plack is like Ruby's Rack or Python's Paste for
WSGI.")
    (license (package-license perl))))

(define-public perl-plack-middleware-fixmissingbodyinredirect
  (package
    (name "perl-plack-middleware-fixmissingbodyinredirect")
    (version "0.12")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/S/SW/SWEETKID/"
                           "Plack-Middleware-FixMissingBodyInRedirect-"
                           version ".tar.gz"))
       (sha256
        (base32
         "14dkrmccq7a5vpymx5dv8032gfcvhsw2i6v5sh3c4ym5ymlx08kc"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-html-parser" ,perl-html-parser) ;for HTML::Entities
       ("perl-http-message" ,perl-http-message)
       ("perl-plack" ,perl-plack)))     ;for Plack::Test
    (home-page
     "http://search.cpan.org/dist/Plack-Middleware-FixMissingBodyInRedirect")
    (synopsis "Plack::Middleware which sets body for redirect response")
    (description "This module sets the body in redirect response, if it's not
already set.")
    (license (package-license perl))))

(define-public perl-plack-middleware-methodoverride
  (package
    (name "perl-plack-middleware-methodoverride")
    (version "0.11")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/D/DW/DWHEELER/"
                           "Plack-Middleware-MethodOverride-"
                           version ".tar.gz"))
       (sha256
        (base32
         "1hb8dx7i4vs74n0p737wrvpdnnw6argxrjpr6kj6432zabp8325z"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-plack" ,perl-plack)))
    (home-page "http://search.cpan.org/dist/Plack-Middleware-MethodOverride")
    (synopsis "Override REST methods to Plack apps via POST")
    (description "This middleware allows for POST requests that pretend to be
something else: by adding either a header named X-HTTP-Method-Override to the
request, or a query parameter named x-tunneled-method to the URI, the client
can say what method it actually meant.")
    (license (package-license perl))))

(define-public perl-plack-middleware-removeredundantbody
  (package
    (name "perl-plack-middleware-removeredundantbody")
    (version "0.05")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/S/SW/SWEETKID/"
                           "Plack-Middleware-RemoveRedundantBody-"
                           version ".tar.gz"))
       (sha256
        (base32
         "1n3wm0zi8dnk54jx937asl951lslj3jvw0fry4jpzsibg4f6wrx0"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-plack" ,perl-plack)))
    (home-page
     "http://search.cpan.org/dist/Plack-Middleware-RemoveRedundantBody")
    (synopsis "Plack::Middleware which removes body for HTTP response")
    (description "This module removes the body in an HTTP response if it's not
required.")
    (license (package-license perl))))

(define-public perl-plack-middleware-reverseproxy
  (package
    (name "perl-plack-middleware-reverseproxy")
    (version "0.15")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/M/MI/MIYAGAWA/"
                           "Plack-Middleware-ReverseProxy-"
                           version ".tar.gz"))
       (sha256
        (base32
         "1zmsccdy6wr5hxzj07r1nsmaymyibk87p95z0wzknjw10lwmqs9f"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-plack" ,perl-plack)))
    (home-page "http://search.cpan.org/dist/Plack-Middleware-ReverseProxy")
    (synopsis "Supports app to run as a reverse proxy backend")
    (description "Plack::Middleware::ReverseProxy resets some HTTP headers,
which are changed by reverse-proxy.  You can specify the reverse proxy address
and stop fake requests using 'enable_if' directive in your app.psgi.")
    (license (package-license perl))))

(define-public perl-plack-test-externalserver
  (package
    (name "perl-plack-test-externalserver")
    (version "0.01")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/F/FL/FLORA/"
                           "Plack-Test-ExternalServer-" version ".tar.gz"))
       (sha256
        (base32
         "1dbg1p3rgvvbkkpvca5jlc2mzx8iqyiybk88al93pvbca65h1g7h"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-plack" ,perl-plack)))
    (home-page "http://search.cpan.org/dist/Plack-Test-ExternalServer")
    (synopsis "Run HTTP tests on external live servers")
    (description "This module allows your to run your Plack::Test tests
against an external server instead of just against a local application through
either mocked HTTP or a locally spawned server.")
    (license (package-license perl))))

(define-public perl-test-tcp
  (package
    (name "perl-test-tcp")
    (version "2.06")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/T/TO/TOKUHIROM/"
                           "Test-TCP-" version ".tar.gz"))
       (sha256
        (base32
         "0acjwm21y2an4f3fasci9qa0isakh9cgp74fk0bzcdi506xmcjbi"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-test-sharedfork" ,perl-test-sharedfork)))
    (arguments `(#:tests? #f))          ;related to signaling in t/05_sigint.t
    (home-page "http://search.cpan.org/dist/Test-TCP")
    (synopsis "Testing TCP programs")
    (description "Test::TCP is test utilities for TCP/IP programs.")
    (license (package-license perl))))

(define-public perl-test-www-mechanize
  (package
    (name "perl-test-www-mechanize")
    (version "1.44")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/P/PE/PETDANCE/"
                           "Test-WWW-Mechanize-" version ".tar.gz"))
       (sha256
        (base32
         "062pj242vsc73bw11jqpap92ax9wzc9f2m4xhyp1wzrwkfchpl2q"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-exception" ,perl-test-exception)))
    (propagated-inputs
     `(("perl-carp-assert-more" ,perl-carp-assert-more)
       ("perl-html-form" ,perl-html-form)
       ("perl-html-lint" ,perl-html-lint)
       ("perl-html-tree" ,perl-html-tree)
       ("perl-http-server-simple" ,perl-http-server-simple)
       ("perl-libwww" ,perl-libwww)
       ("perl-test-longstring" ,perl-test-longstring)
       ("perl-www-mechanize" ,perl-www-mechanize)))
    (home-page "http://search.cpan.org/dist/Test-WWW-Mechanize")
    (synopsis "Testing-specific WWW::Mechanize subclass")
    (description "Test::WWW::Mechanize is a subclass of the Perl module
WWW::Mechanize that incorporates features for web application testing.")
    (license l:artistic2.0)))

(define-public perl-test-www-mechanize-catalyst
  (package
    (name "perl-test-www-mechanize-catalyst")
    (version "0.60")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/J/JJ/JJNAPIORK/"
                           "Test-WWW-Mechanize-Catalyst-" version ".tar.gz"))
       (sha256
        (base32
         "0nhhfrrai3ndziz873vpa1j0vljjnib4wqafd6yyvkf58ad7v0lv"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-catalyst-plugin-session" ,perl-catalyst-plugin-session)
       ("perl-catalyst-plugin-session-state-cookie"
        ,perl-catalyst-plugin-session-state-cookie)
       ("perl-test-exception" ,perl-test-exception)
       ("perl-test-pod" ,perl-test-pod)
       ("perl-test-utf8" ,perl-test-utf8)))
    (propagated-inputs
     `(("perl-catalyst-runtime" ,perl-catalyst-runtime)
       ("perl-class-load" ,perl-class-load)
       ("perl-libwww" ,perl-libwww)
       ("perl-moose" ,perl-moose)
       ("perl-namespace-clean" ,perl-namespace-clean)
       ("perl-test-www-mechanize" ,perl-test-www-mechanize)
       ("perl-www-mechanize" ,perl-www-mechanize)))
    (home-page "http://search.cpan.org/dist/Test-WWW-Mechanize-Catalyst")
    (synopsis "Test::WWW::Mechanize for Catalyst")
    (description "The Test::WWW::Mechanize::Catalyst module meshes the
Test::WWW:Mechanize module and the Catalyst web application framework to allow
testing of Catalyst applications without needing to start up a web server.")
    (license (package-license perl))))

(define-public perl-test-www-mechanize-psgi
  (package
    (name "perl-test-www-mechanize-psgi")
    (version "0.35")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/L/LB/LBROCARD/"
                           "Test-WWW-Mechanize-PSGI-" version ".tar.gz"))
       (sha256
        (base32
         "1hih8s49zf38bisvhnhzrrj0zwyiivkrbs7nmmdqm1qqy27wv7pc"))))
    (build-system perl-build-system)
    (native-inputs
     `(("perl-test-pod" ,perl-test-pod)))
    (propagated-inputs
     `(("perl-plack" ,perl-plack)
       ("perl-test-www-mechanize" ,perl-test-www-mechanize)))
    (home-page "http://search.cpan.org/dist/Test-WWW-Mechanize-PSGI")
    (synopsis "Test PSGI programs using WWW::Mechanize")
    (description "PSGI is a specification to decouple web server environments
from web application framework code.  Test::WWW::Mechanize is a subclass of
WWW::Mechanize that incorporates features for web application testing.  The
Test::WWW::Mechanize::PSGI module meshes the two to allow easy testing of PSGI
applications.")
    (license (package-license perl))))

(define-public perl-uri
  (package
    (name "perl-uri")
    (version "1.67")
    (source (origin
             (method url-fetch)
             (uri (string-append "mirror://cpan/authors/id/E/ET/ETHER/"
                                 "URI-" version ".tar.gz"))
             (sha256
              (base32
               "0ki7i830gs0cwwwjsyv3s6yy1l76ym8pfqp0lp7vw0j9bwyx923h"))))
    (build-system perl-build-system)
    (license (package-license perl))
    (synopsis "Perl Uniform Resource Identifiers (absolute and relative)")
    (description
     "The URI module implements the URI class.  Objects of this class
represent \"Uniform Resource Identifier references\" as specified in RFC 2396
and updated by RFC 2732.")
    (home-page "http://search.cpan.org/dist/URI/")))

(define-public perl-uri-find
  (package
    (name "perl-uri-find")
    (version "20140709")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/M/MS/MSCHWERN/"
                           "URI-Find-" version ".tar.gz"))
       (sha256
        (base32
         "0czc4h182s7sx3k123m7qlg7yybnwxgh369hap3c3b6xgrglrhy0"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-uri" ,perl-uri)))
    (home-page "http://search.cpan.org/dist/URI-Find")
    (synopsis "Find URIs in arbitrary text")
    (description "This module finds URIs and URLs (according to what URI.pm
considers a URI) in plain text.  It only finds URIs which include a
scheme (http:// or the like), for something a bit less strict, consider
URI::Find::Schemeless.  For a command-line interface, urifind is provided.")
    (license (package-license perl))))

(define-public perl-uri-ws
  (package
    (name "perl-uri-ws")
    (version "0.03")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/P/PL/PLICEASE/"
                           "URI-ws-" version ".tar.gz"))
       (sha256
        (base32
         "1vs1wm80sq685944g1l4a0fxcbccc00c0f9648yabdmcf90hwsvf"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-uri" ,perl-uri)))
    (home-page "http://search.cpan.org/dist/URI-ws")
    (synopsis "WebSocket support for URI package")
    (description "With this module, the URI package provides the same set of
methods for WebSocket URIs as it does for HTTP URIs.")
    (license (package-license perl))))

(define-public perl-www-curl
  (package
    (name "perl-www-curl")
    (version "4.17")
    (source (origin
              (method url-fetch)
              (uri (string-append
                    "mirror://cpan/authors/id/S/SZ/SZBALINT/WWW-Curl-"
                    version".tar.gz"))
              (sha256
               (base32
                "1fmp9aib1kaps9vhs4dwxn7b15kgnlz9f714bxvqsd1j1q8spzsj"))))
    (build-system perl-build-system)
    (arguments
     '(#:tests? #f))                        ;XXX: tests require network access
    (inputs `(("curl" ,curl)))
    (synopsis "Perl extension interface for libcurl")
    (description
     "This is a Perl extension interface for the libcurl file downloading
library.")
    (license (package-license perl))
    (home-page "http://search.cpan.org/~szbalint/WWW-Curl-4.17/lib/WWW/Curl.pm")))

(define-public perl-www-mechanize
  (package
    (name "perl-www-mechanize")
    (version "1.73")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://cpan/authors/id/E/ET/ETHER/"
                           "WWW-Mechanize-" version ".tar.gz"))
       (sha256
        (base32
         "1zrw8aadhwy48q51x2z2rqlkwf17bya4j4h3hy89mw783j96rmg9"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-html-form" ,perl-html-form)
       ("perl-html-parser" ,perl-html-parser)
       ("perl-http-message" ,perl-http-message)
       ("perl-http-server-simple" ,perl-http-server-simple)
       ("perl-libwww" ,perl-libwww)
       ("perl-test-warn" ,perl-test-warn)
       ("perl-uri" ,perl-uri)))
    (home-page "http://search.cpan.org/dist/WWW-Mechanize")
    (synopsis "Web browsing in a Perl object")
    (description "WWW::Mechanize is a Perl module for stateful programmatic
web browsing, used for automating interaction with websites.")
    (license (package-license perl))))

(define-public perl-www-robotrules
  (package
    (name "perl-www-robotrules")
    (version "6.02")
    (source (origin
             (method url-fetch)
             (uri (string-append
                   "mirror://cpan/authors/id/G/GA/GAAS/WWW-RobotRules-"
                   version ".tar.gz"))
             (sha256
              (base32
               "07m50dp5n5jxv3m93i55qvnd67a6g7cvbvlik115kmc8lbkh5da6"))))
    (build-system perl-build-system)
    (propagated-inputs
     `(("perl-uri" ,perl-uri)))
    (license (package-license perl))
    (synopsis "Perl database of robots.txt-derived permissions")
    (description
     "The WWW::RobotRules module parses /robots.txt files as specified in
\"A Standard for Robot Exclusion\", at
<http://www.robotstxt.org/wc/norobots.html>.  Webmasters can use the
/robots.txt file to forbid conforming robots from accessing parts of
their web site.")
    (home-page "http://search.cpan.org/~gaas/WWW-RobotRules/")))

(define-public r-httpuv
  (package
    (name "r-httpuv")
    (version "1.3.3")
    (source (origin
              (method url-fetch)
              (uri (cran-uri "httpuv" version))
              (sha256
               (base32
                "0aibs0hf38n8f6xxx4g2i2lzd6l5h92m5pscx2z834sdvhnladxv"))))
    (build-system r-build-system)
    (native-inputs `(("r-rcpp" ,r-rcpp)))
    (home-page "https://github.com/rstudio/httpuv")
    (synopsis "HTTP and WebSocket server library for R")
    (description
     "The httpuv package provides low-level socket and protocol support for
handling HTTP and WebSocket requests directly from within R.  It is primarily
intended as a building block for other packages, rather than making it
particularly easy to create complete web applications using httpuv alone.")
    ;; This package includes third-party code that was originally released
    ;; under various non-copyleft licenses.  Full licensing information can be
    ;; obtained here: https://github.com/rstudio/httpuv/blob/master/LICENSE
    (license l:gpl3+)))

(define-public r-jsonlite
  (package
    (name "r-jsonlite")
    (version "0.9.17")
    (source (origin
              (method url-fetch)
              (uri (cran-uri "jsonlite" version))
              (sha256
               (base32
                "07s11m8z43dh5pyci5rpjqj5js69q8prjar42qhhxbvdmcrjk4z7"))))
    (build-system r-build-system)
    (home-page "http://arxiv.org/abs/1403.2805")
    (synopsis "Robust, high performance JSON parser and generator for R")
    (description
     "The jsonlite package provides a fast JSON parser and generator optimized
for statistical data and the web.  It offers flexible, robust, high
performance tools for working with JSON in R and is particularly powerful for
building pipelines and interacting with a web API.  In addition to converting
JSON data from/to R objects, jsonlite contains functions to stream, validate,
and prettify JSON data.  The unit tests included with the package verify that
all edge cases are encoded and decoded consistently for use with dynamic data
in systems and applications.")
    (license l:expat)))

(define-public r-servr
  (package
    (name "r-servr")
    (version "0.2")
    (source (origin
              (method url-fetch)
              (uri (cran-uri "servr" version))
              (sha256
               (base32
                "0gah99snaj8lk5zfzbxi3jwvpnlff9diz9gqv4qalfxpmb7fp6lc"))))
    (build-system r-build-system)
    (propagated-inputs
     `(("r-httpuv" ,r-httpuv)
       ("r-jsonlite" ,r-jsonlite)
       ("r-mime" ,r-mime)))
    (native-inputs
     `(("r-rcpp" ,r-rcpp)))
    (home-page "https://github.com/yihui/servr")
    (synopsis "Simple HTTP server to serve static files or dynamic documents")
    (description
     "Servr provides an HTTP server in R to serve static files, or dynamic
documents that can be converted to HTML files (e.g., R Markdown) under a given
directory.")
    (license l:expat)))

(define-public r-htmltools
  (package
    (name "r-htmltools")
    (version "0.2.6")
    (source (origin
              (method url-fetch)
              (uri (cran-uri "htmltools" version))
              (sha256
               (base32
                "1gp6f6388xy3cvnb08q08vraidjp740gfxlafdd19m2s04v5hncz"))))
    (build-system r-build-system)
    (propagated-inputs
     `(("r-digest" ,r-digest)))
    (home-page "http://cran.r-project.org/web/packages/htmltools")
    (synopsis "R tools for HTML")
    (description
     "This package provides tools for HTML generation and output in R.")
    (license l:expat)))

(define-public r-htmlwidgets
  (package
    (name "r-htmlwidgets")
    (version "0.5")
    (source (origin
              (method url-fetch)
              (uri (cran-uri "htmlwidgets" version))
              (sha256
               (base32
                "1d583kk7g29r4sq0y1scri7fs48z6q17c051nyjywcvnpy4lvi8j"))))
    (build-system r-build-system)
    (propagated-inputs
     `(("r-htmltools" ,r-htmltools)
       ("r-jsonlite" ,r-jsonlite)
       ("r-yaml" ,r-yaml)))
    (home-page "https://github.com/ramnathv/htmlwidgets")
    (synopsis "HTML Widgets for R")
    (description
     "HTML widgets is a framework for creating HTML widgets that render in
various contexts including the R console, R Markdown documents, and Shiny web
applications.")
    (license l:expat)))

(define-public r-curl
  (package
    (name "r-curl")
    (version "0.9.3")
    (source (origin
              (method url-fetch)
              (uri (cran-uri "curl" version))
              (sha256
               (base32
                "02p9s1jlk8dcbvn71ivn4xnrqh9dwqyhgn4s1fzcfmnmfxhl5gld"))))
    (build-system r-build-system)
    (inputs
     `(("libcurl" ,curl)))
    (home-page "https://github.com/jeroenooms/curl")
    (synopsis "HTTP client for R")
    (description
     "The @code{curl()} and @code{curl_download()} functions provide highly
configurable drop-in replacements for base @code{url()} and
@code{download.file()} with better performance, support for encryption, gzip
compression, authentication, and other @code{libcurl} goodies.  The core of
the package implements a framework for performing fully customized requests
where data can be processed either in memory, on disk, or streaming via the
callback or connection interfaces.")
    (license l:expat)))

(define-public gumbo-parser
  (package
    (name "gumbo-parser")
    (version "0.10.1")
    (source (origin
              (method url-fetch)
              (uri (string-append "https://github.com/google/"
                                  "gumbo-parser/archive/v" version ".tar.gz"))
              (file-name (string-append name "-" version ".tar.gz"))
              (sha256
               (base32
                "1bgg2kbj311pqdzw2v33za7k66g1rv44kkvvnz2gnpaasi9k0ii8"))))
    (build-system gnu-build-system)
    (arguments
     `(#:tests? #f ; tests require bundling googletest sources
       #:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'bootstrap
          (lambda _ (zero? (system* "sh" "autogen.sh")))))))
    ;; The release tarball lacks the generated files.
    (native-inputs
     `(("autoconf" ,autoconf)
       ("automake" ,automake)
       ("libtool" ,libtool)))
    (home-page "https://github.com/google/gumbo-parser")
    (synopsis "HTML5 parsing library")
    (description
     "Gumbo is an implementation of the HTML5 parsing algorithm implemented as
a pure C99 library.")
    (license l:asl2.0)))
