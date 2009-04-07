;;; compile-bookmarks.el --- bookmarks for compilation commands
;;
;; Copyright (C) 2008 Nikolaj Schumacher
;;
;; Author: Nikolaj Schumacher <bugs * nschum de>
;; Version: 0.2
;; Keywords: tools, processes
;; URL: http://nschum.de/src/emacs/compile-bookmarks/
;; Compatibility: GNU Emacs 22.x
;;
;; This file is NOT part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;; compile-bookmarks.el allows you to bookmark your compile commands and retain
;; them across sessions.
;;
;; When you enable the global `compile-bookmarks-mode', your bookmarks will be
;; loaded from `compile-bm-save-file'.  If you quit emacs with the mode enabled,
;; the bookmarks will be stored automatically.
;;
;; You can manage your bookmarks with `compile-bm-add', `compile-bm-remove' and
;; `compile-bm-recompile', or use the "Compile" menu.
;;
;; Keys can be assigned to bookmarks as well.  All keybindings are added to
;; `compile-bm-shortcut-map', which is bound to C-c <f8> by default.
;; To change this prefix key, you can add the following to you .emacs:
;;
;; (define-key compile-bookmarks-mode-map (kbd "C-c <f5>")
;;             compile-bm-shortcut-map)
;;
;;; Change Log:
;;
;; 2008-06-15 (0.2)
;;    Added keybinding for bookmarks.
;;    Fixed force argument in `compile-bm-load-list'.
;;    Added Storing and recovering of last active compile command.
;;
;; 2008-06-09 (0.1)
;;    Initial release.
;;
;;; Code:

(require 'compile)

(defgroup compile-bookmarks nil
  "Bookmarks for compilation commands"
  :group 'tools
  :group 'processes)

(defcustom compile-bm-save-file
  (if (fboundp 'locate-user-emacs-file)
      (locate-user-emacs-file "compile-bookmarks" ".compile-bm")
    "~/.compile-bm")
  "*File name for storing the compilation bookmarks"
  :group 'compile-bookmarks
  :type 'file)

(defvar compile-bm-shortcut-map (make-keymap)
  "Keymap containing bookmarked compilation commands.")

(defvar compile-bookmarks-mode-map
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap (kbd "C-c <f8>") compile-bm-shortcut-map)
    keymap)
  "*Keymap used by `compile-bm-mode'.")
(defvaralias 'compile-bm-mode-map 'compile-bookmarks-mode-map)

(defvar compile-bm-list nil
  "The bookmarks for `compile-bookmarks-mode'.")

(require 'recentf)
(defalias 'compile-bm-dump-variable 'recentf-dump-variable)

(defun compile-bm-save-list ()
  "Store the saved bookmarks to `compile-bm-save-file'."
  ;; based on recentf-save-list
  (with-temp-buffer
    (erase-buffer)
    (set-buffer-file-coding-system 'emacs-mule)
    (insert (format ";;; Generated by `compile-bm' on %s"
                    (current-time-string)))
    (compile-bm-dump-variable 'compile-bm-list)
    ;; store current selection
    ;; use fake names, so loading the file doesn't override the actual values
    (let ((compile-bm-directory compilation-directory)
          (compile-bm-command compile-command))
      (compile-bm-dump-variable 'compile-bm-directory)
      (compile-bm-dump-variable 'compile-bm-command))
    (insert "\n\n;;; Local Variables:\n"
            (format ";;; coding: %s\n" 'emacs-mule)
            ";;; End:\n")
    (write-file (expand-file-name compile-bm-save-file))))

(defun compile-bm-load-list (&optional force)
  "Load the previously saved bookmarks from `recentf-save-file'.
Unless optional argument FORCE is given, the command will fail if
`compile-bm-list' already contains any values."
  (and compile-bm-list (not force)
       (error "Refusing to overwrite existing bookmarks"))
  (let ((file (expand-file-name compile-bm-save-file))
        compile-bm-directory compile-bm-command)
    (when (file-readable-p file)
      (load-file file))
    (dolist (entry compile-bm-list)
      (if (consp (cdr entry))
          (compile-bm-assign-key (caar entry) (cdar entry)
                                 (compile-bm-entry-char entry))
        ;; convert old format
        (setcdr entry (cons (cdr entry) nil))))
    (unless compilation-directory
      ;; no compilation command set, recover old one
      (setq compilation-directory compile-bm-directory)
      (when compile-bm-command
        (setq compile-command compile-bm-command)))))

(defsubst compile-bm-lookup (directory command)
  (assoc (cons directory command) compile-bm-list))

(defsubst compile-bm-entry-name (entry)
  (cadr entry))

(defsubst compile-bm-entry-char (entry)
  (nth 2 entry))

(defun compile-bm-assign-key (directory command char)
  (when char
    (define-key compile-bm-shortcut-map (vector char)
      (when (and directory command)
        `(lambda (arg)
           (interactive "P")
           (when arg (compile-bm-restore ,directory ,command))
           (let ((compilation-directory ,directory)
                 (compile-command ,command))
             (recompile)))))))

(defun compile-bm-suggest-name (directory command)
  (concat
   (mapconcat 'identity (last (split-string directory "/" t) 2) "/")
   " | "
   (if (> (length command) 40)
       (concat "..." (substring command -37))
     command)))

(defsubst compile-bm-read-name (directory command)
  (read-from-minibuffer "Name: "
                        (or (compile-bm-entry-name
                             (compile-bm-lookup directory command))
                            (compile-bm-suggest-name directory command))))

(defun compile-bm-add (directory command name &optional char)
  "Add the current `compile-command' to the saved command list."
  (interactive (list compilation-directory compile-command
                     (compile-bm-read-name compilation-directory
                                           compile-command)
                     (let ((char (read-char-exclusive
                                  "Character (ESC for none): ")))
                       (when (/= char 27) char))))
  (let ((pair (cons compilation-directory compile-command))
        (entry (compile-bm-lookup compilation-directory compile-command))
        (metadata (list name char)))
    (if entry
        (progn
          ;; remove old keybinding
          (compile-bm-assign-key nil nil (compile-bm-entry-char entry))
          (setcdr entry metadata))
      (push (cons pair metadata) compile-bm-list)))
  ;; add keybinding
  (compile-bm-assign-key directory command char)
  (setq compile-bm-list
        (sort compile-bm-list (lambda (a b)
                                (string< (compile-bm-entry-name a)
                                         (compile-bm-entry-name b)))))
  (compile-bm-update-menu))

(defun compile-bm-make-menu-entry (entry)
  (let ((name (compile-bm-entry-name entry))
        (char (compile-bm-entry-char entry)))
    (when char
      ;; show bound key
      (setq name
            (concat name "\t("
                    (key-description
                     (car (where-is-internal compile-bm-shortcut-map)))
                    " " (string char) ")")))
    (vector
     name
     `(compile-bm-restore-and-compile (quote ,entry))
     :style 'toggle
     :selected `(and (equal ,(caar entry) compilation-directory)
                     (equal ,(cdar entry) compile-command)))))

(defun compile-bm-update-menu ()
  (easy-menu-define compile-bm-menu compile-bm-mode-map
    "Compile Bookmarks"
    `("Compile"
      ,@(mapcar 'compile-bm-make-menu-entry compile-bm-list)
      "-"
      ["Modify" compile-bm-add
       :visible (compile-bm-lookup compilation-directory compile-command)]
      ["Remove" compile-bm-remove
       :visible (compile-bm-lookup compilation-directory compile-command)]
      ["Add" compile-bm-add
       :visible (and compilation-directory
                     (not (compile-bm-lookup compilation-directory
                                             compile-command)))]
      ))
  (easy-menu-add compile-bm-menu))

;;;###autoload
(define-minor-mode compile-bookmarks-mode
  "Minor mode for keeping track of multiple `compile-command's.
This mode enables a bookmark menu for the commands used by `recompile'.
Once you have stored the last compilation with `compile-bm-add' (or the
menu), you will be able to execute that compilation from the menu."
  nil nil compile-bookmarks-mode-map :global t
  (if compile-bookmarks-mode
      (progn (compile-bm-load-list)
             (add-hook 'kill-emacs-hook 'compile-bm-save-list)
             (compile-bm-update-menu))
    (compile-bm-save-list)
    ;; delete list, so not to trigger overwrite warning when enabling again
    (setq compile-bm-list nil)
    (remove-hook 'kill-emacs-hook 'compile-bm-save-list)))

(defalias 'compile-bm-mode 'compile-bookmarks-mode)

(defun compile-bm-remove ()
  "Remove the current `compile-command' from the saved command list."
  (interactive)
  (setq compile-bm-list
        (delete (compile-bm-lookup compilation-directory compile-command)
                compile-bm-list))
  (compile-bm-update-menu))

(defun compile-bm-restore (directory command)
  "Restore ENTRY from `compile-bm-list'."
  (setq compilation-directory directory)
  (setq compile-command command)
  (compile-bm-update-menu))

(defun compile-bm-restore-and-compile (entry)
  "Restore ENTRY from `compile-bm-list' and compile."
  (compile-bm-restore (caar entry) (cdar entry))
  (recompile))

(defsubst compile-bm-swap (c)
  (cons (cdr c) (car c)))

(defun compile-bm-recompile ()
  "Pick a compile bookmark and compile."
  (interactive)
  (let* ((swapped (mapcar 'compile-bm-swap compile-bm-list))
         (history (mapcar 'cdr compile-bm-list)))
    (compile-bm-restore-and-compile
     (compile-bm-swap
      (assoc (completing-read "Compile: " swapped nil t nil 'history)
             swapped)))))

(provide 'compile-bookmarks)
;;; compile-bookmarks.el ends here
