from ranger.api.commands import Command

class paste_as_root(Command):
	def execute(self):
		if self.fm.do_cut:
			self.fm.execute_console('shell sudo mv %c .')
		else:
			self.fm.execute_console('shell sudo cp -r %c .')

class fzf_select(Command):
    """
    :fzf_select

    Find a file using fzf.

    With a prefix argument select only directories.

    See: https://github.com/junegunn/fzf
    """
    def execute(self):
        import subprocess
        import os.path
        if self.quantifier:
            # match only directories
            command="find -L . \\( -path '*/\\.*' -o -fstype 'dev' -o -fstype 'proc' \\) -prune \
            -o -type d -print 2> /dev/null | sed 1d | cut -b3- | fzf +m --reverse --header='Jump to file'"
        else:
            # match files and directories
            command="find -L . \\( -path '*/\\.*' -o -fstype 'dev' -o -fstype 'proc' \\) -prune \
            -o -print 2> /dev/null | sed 1d | cut -b3- | fzf +m --reverse --header='Jump to filemap <C-f> fzf_select'"
        fzf = self.fm.execute_command(command, universal_newlines=True, stdout=subprocess.PIPE)
        stdout, stderr = fzf.communicate()
        if fzf.returncode == 0:
            fzf_file = os.path.abspath(stdout.rstrip('\n'))
            if os.path.isdir(fzf_file):
                self.fm.cd(fzf_file)
            else:
                self.fm.select_file(fzf_file)


class trash(Command):
    """
    :trash

    Move the selection to the freedesktop trash. Recoverable with :restore.
    Bound to dD, <DELETE> and <F8>; :delete still removes permanently.
    """
    def execute(self):
        import subprocess
        selection = self.fm.thistab.get_selection()
        if not selection:
            self.fm.notify("Nothing selected", bad=True)
            return
        paths = [f.path for f in selection]
        try:
            subprocess.check_call(["trash-put", "--"] + paths)
        except OSError:
            self.fm.notify("trash-put not found - install trash-cli", bad=True)
            return
        except subprocess.CalledProcessError as err:
            self.fm.notify("trash-put failed (exit %d)" % err.returncode, bad=True)
            return
        self.fm.notify("Trashed %d item(s) - :restore to undo" % len(paths))
        self.fm.thisdir.load_content()


class restore(Command):
    """
    :restore

    Interactively restore files from the trash.
    """
    def execute(self):
        self.fm.execute_console("shell -w trash-restore")