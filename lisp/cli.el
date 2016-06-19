;;; cli -- cli -*- lexical-binding: t; coding: utf-8; -*-

;; Commentary:

;;; Code:

(require 'cl-lib)
(require 'pcase)
(require 'seq)

(defconst emb-prefix
  (expand-file-name
   ".emb"
   (getenv "HOME")))

(cl-defmacro with-directory (dir &body body)
  `(cl-letf ((default-directory ,dir))
     ,@body))

(cl-defun create-directory! (dir)
  (pcase (file-exists-p dir)
    (`nil
     (make-directory dir))
    (_ t)))

(cl-defun init-prefix (prefix)
  (pcase (file-exists-p prefix)
    (`nil
     (princ "* Creating prefix directory...")
     (create-directory! prefix)
     (terpri))))

(cl-defun exec-print (com)
  (princ (shell-command-to-string com)))

(cl-defun exec (com)
  (shell-command-to-string com))

(cl-defun command-ls (prefix args)
  (with-directory prefix
    (exec-print "ls")))

(cl-defun init-get (dir)
  (pcase (file-exists-p dir)
    (`nil
     (princ "* Creating tmp directory...")
     (create-directory! dir)
     (terpri))
    (_ t)))

(cl-defun command-get (prefix args)
  (cl-letf ((get-prefix
             (expand-file-name
              "tmp" prefix)))
    (init-get get-prefix)
    (pcase (file-exists-p (prefix-get prefix (car args)))
      (`nil
       (princ "* Cloning emacs repository...")
       (terpri)
       (with-directory get-prefix
         (exec-print (concat "git clone --depth 1 "
                             "https://github.com/emacs-mirror/emacs.git"
                             " "
                             (prefix-get prefix (car args)))))
       (terpri))
      (_
       (princ "* Already fetched")
       (terpri)))))

(cl-defun prefix-get (prefix ver)
  (cl-letf ((get-prefix
             (expand-file-name
              "tmp" prefix))
            (clone-version
             (pcase ver
               ((or "master" "git") "emacs-master")
               (_ "emacs-master"))))
    (expand-file-name clone-version get-prefix)))

(cl-defun prefix-build (prefix ver)
  (expand-file-name
   ver
   (expand-file-name
    "build"
    prefix)))

(cl-defun princ-newline (str)
  (princ str)
  (terpri))


(cl-defun command-build-make (prefix args)
  (remove-directory! (prefix-build prefix (car args)))
  (with-directory (prefix-get prefix (car args))
    (princ-newline "* Updating repository")
    (exec-print "git pull")
    (princ-newline "* Configuring emacs...")
    (exec "./autogen.sh all")
    (exec (concat "./configure "
                  " --prefix="
                  (prefix-build prefix (car args))
                  " "
                  " --disable-acl "
                  " --with-sound=oss "
                  " --with-x-toolkit=no "
                  " --without-cairo "
                  " --with-wide-int "
                  " --enable-link-time-optimization "
                  " --enable-silent-rules "
                  " --with-modules "
                  " --program-prefix=\"emb-\""
                  " --without-png"
                  " --without-jpeg"
                  " --without-dbus"
                  " --without-gconf"
                  " --without-gif"
                  " --without-rsvg"
                  " --without-tiff"
                  " --without-toolkit-scroll-bars"
                  " --without-xft"
                  " --without-xim"
                  " --without-xpm"
                  " --without-imagemagick"
                  " --without-gsettings"
                  " --without-pop"
                  " --without-libsystemd"    
                  " --without-libotf"        
                  " --without-xaw3d"         
                  " --without-gpm"           
                  " --without-makeinfo"
                  " CC=clang-devel MAKE=gmake CFLAGS='-O2'"))
    (princ-newline "* Building emacs...")
    (exec "gmake V=0 --silent")
    (princ "* Installing emacs...")
    (exec "gmake install")))

(cl-defun command-build-make-install (prefix args)
  (with-directory (prefix-get prefix (car args))
    (princ "* Installing emacs...")
    (exec "gmake install")))

(cl-defun prefix-link (prefix)
  (expand-file-name "shims"
                    prefix))


(cl-defun init-link (base)
  (cl-labels ((mkd (dir)
                (pcase (file-exists-p dir)
                  (`nil
                   (princ (concat "* Creating " dir "..."))
                   (create-directory! dir)
                   (terpri))
                  (_ t))))
    (mkd  base)
    (mkd (expand-file-name "bin" base))
    (mkd (expand-file-name "man" base))))


(cl-defun list-files (dir)
  (seq-remove
   (lambda (d)
     (pcase (file-name-base d)
       ((or "." "..")
        t)
       (_
        nil)))
   (directory-files dir 'full)))


(cl-defun command-link (prefix args)
  (init-link (prefix-link prefix))
  (cl-letf* ((ver (car args))
             (build-prefix
              (prefix-build prefix ver))
             (build-bin
              (expand-file-name
               "bin" build-prefix)))
    (seq-each
     (lambda (target)
       (make-symbolic-link
        target
        (expand-file-name (file-name-base target)
                          (expand-file-name
                           "bin"
                           (prefix-link prefix)))
        'OK-IF-ALREADY-EXISTS))
     (list-files build-bin))))

(cl-defun remove-directory! (dir)
  (pcase (file-exists-p dir)
    (`nil t)
    (_
     (princ (concat "* Removing directory " dir))
     (delete-directory dir 'recursive)
     (terpri))))

(cl-defun command-deinstall (prefix args)
  (cl-letf* ((build-dir (prefix-build prefix (car args)))
             (shims-dir (prefix-link prefix))
             (shims-bin-dir (expand-file-name "bin" shims-dir))
             (shims-bins (list-files shims-bin-dir)))
    (seq-each
     (lambda (f)
       (princ (concat "* Removing files " f))
       (delete-file f)
       (terpri))
     shims-bins)
    (remove-directory! build-dir)))

(cl-defun command-clean (prefix args)
  (remove-directory!
   (prefix-get prefix (car args)))) 

(cl-defun command-help ()
  (princ-newline
   " commands: get ls clean link build install reinstall deinstall

    emb get version
    emb ls [version]
    emb clean [version]
    emb link version
    emb build version
    emb install version
    emb deinstall version
    emb reinstall version "))


(cl-defun main (prefix args)
  (init-prefix prefix)
  (cl-letf ((rargs (cdr args)))
    (pcase (car args)
      ("build"
       (command-build prefix rargs))
      ("install"
       (command-get prefix rargs)
       (command-build prefix rargs)
       (command-link prefix rargs))
      ("reinstall"
       (command-clean prefix rargs)
       (command-get prefix rargs)
       (command-build-make prefix rargs)
       (command-deinstall prefix rargs)
       (command-build-make-install prefix rargs)
       (command-link prefix rargs))
      ("get"
       (command-get prefix rargs))
      ("ls"
       (command-ls prefix rargs))
      ("clean"
       (command-clean prefix rargs))
      ("link"
       (command-link prefix rargs))
      ("deinstall"
       (command-deinstall prefix rargs))
      ("help"
       (command-help))
      (_
       (command-help)))))

(main emb-prefix (cdr command-line-args-left))

;;; cli.el ends here
