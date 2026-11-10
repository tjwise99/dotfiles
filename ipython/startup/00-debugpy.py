# VS Code's notebook debugger cannot attach to child processes. With debugpy's default
# subProcess=True, any child Python a cell starts (subprocess.run([sys.executable, ...]))
# is rewritten to wait for a debugger that never connects, hanging the cell. This must run
# before the kernel's debugger first listens, which is why it lives in startup, not a cell.
try:
    import debugpy
except ImportError:
    pass
else:
    debugpy.configure(subProcess=False)
