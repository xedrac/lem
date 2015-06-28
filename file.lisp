(in-package :lem)

(defun file-name-directory (filename)
  (let ((pos (position #\/ filename :from-end t)))
    (when pos
      (subseq filename 0 (1+ pos)))))

(defun file-name-nondirectory (filename)
  (let ((pos (position #\/ filename :from-end t)))
    (if pos
      (subseq filename (1+ pos))
      filename)))

(defun file-name-as-directory (filename)
  (if (char/= #\/ (aref filename (1- (length filename))))
    (concatenate 'string filename "/")
    filename))

(defun current-directory ()
  (if (buffer-filename)
    (file-name-directory
     (buffer-filename))
    (file-name-as-directory (pwd))))

(defun file-exist-p (file-name)
  (if (probe-file file-name)
    t
    nil))

(defun temp-file-name-1 ()
  (concatenate 'string
    "/tmp/"
    *program-name*
    "-"
    (coerce (loop repeat 8
              collect (code-char
                       (random-range
                        (char-code #\a)
                        (char-code #\z))))
      'string)))

(defun temp-file-name ()
  (loop for name = (temp-file-name-1)
    while (file-exist-p name)
    finally (return name)))

(defun expand-file-name (filename &optional directory)
  (when (and (string/= filename "")
             (char/= (aref filename 0) #\/))
    (setq filename
      (concatenate 'string
        (or (and directory (file-name-as-directory directory))
            (current-directory))
        filename)))
  (let ((path))
    (dolist (name (split-string filename #\/))
      (cond
       ((string= ".." name)
        (pop path))
       ((string/= "." name)
        (push name path))))
    (let ((str ""))
      (dolist (p (nreverse path))
        (setq str
          (concatenate 'string
            str "/" p)))
      (subseq str 1))))

(defun file-completion (str)
  (setq str (expand-file-name str))
  (let ((dirname (file-name-directory str)))
    (completion str (files dirname))))

(defun file-open (path)
  (let ((filename (file-name-nondirectory path)))
    (unless (string= "" filename)
      (let ((buffer (make-buffer
                     filename
                     :filename (expand-file-name path))))
        (with-open-file (in (buffer-filename buffer) :if-does-not-exist nil)
          (when in
            (do () (nil)
              (multiple-value-bind (str eof-p) (read-line in nil)
                (if (not eof-p)
                  (buffer-append-line buffer str)
                  (progn
                   (buffer-append-line buffer (or str ""))
                   (return)))))))
        (set-buffer buffer)
        (unmark-buffer)
        t))))

(define-key *global-keymap* "C-xC-f" 'find-file)
(define-command find-file (filename) ("FFind File: ")
  (let ((buf (get-buffer (file-name-nondirectory filename))))
    (cond
     ((null buf)
      (file-open filename))
     ((and (buffer-filename buf)
           (string/= (expand-file-name filename) (buffer-filename buf)))
      (let ((name (uniq-buffer-name filename)))
        (set-buffer (make-buffer (file-name-nondirectory name)
                      :filename filename))))
     (t
      (set-buffer buf)))
    (run-hooks 'find-file-hooks)))

(define-key *global-keymap* "C-xC-r" 'read-file)
(define-command read-file (filename) ("FRead File: ")
  (find-file filename)
  (setf (buffer-read-only-p (window-buffer)) t)
  t)

(defun write-to-file (buffer filename)
  (with-open-file (out filename
                    :direction :output
                    :if-exists :supersede
                    :if-does-not-exist :create)
    (map-buffer-lines (lambda (line eof-p linum)
                        (declare (ignore linum))
                        (princ line out)
                        (unless eof-p
                          (terpri out)))
      buffer)))

(defun save-file-internal (buffer)
  (write-to-file buffer (buffer-filename buffer))
  (unmark-buffer)
  (write-message "Wrote")
  t)

(define-key *global-keymap* "C-xC-s" 'save-file)
(define-command save-file () ()
  (let ((buffer (window-buffer)))
    (cond
     ((null (buffer-modified-p buffer))
      nil)
     ((null (buffer-filename buffer))
      (write-message "No file name")
      nil)
     (t
      (save-file-internal buffer)))))

(define-command change-file-name (filename) ("sChange file name: ")
  (setf (buffer-filename (window-buffer)) filename)
  t)

(define-key *global-keymap* "C-xC-w" 'write-file)
(define-command write-file (filename) ("FWrite File: ")
  (change-file-name filename)
  (save-file-internal (window-buffer)))

(define-key *global-keymap* "C-xC-i" 'insert-file)
(define-command insert-file (filename) ("fInsert file: ")
  (with-open-file (in filename)
    (do ((str #1=(read-line in nil) #1#))
        ((null str))
      (insert-string str)
      (insert-newline 1))
    t))

(defun save-some-buffers ()
  (dolist (buffer *buffer-list*)
    (when (and (buffer-modified-p buffer)
               (buffer-filename buffer))
      (save-file-internal buffer))))
