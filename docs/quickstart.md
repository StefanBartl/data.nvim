# Quickstart

Paste a minified JSON blob into a buffer (or a support ticket already has one on a
single line), put the cursor anywhere in the buffer, and run:

```
:JSON
```

That's `:JSON pretty` with no explicit action — the whole buffer, reformatted
in place, 2-space indent.

A few more:

```
:JSON compact             " back to one line, e.g. to paste into a ticket reply
:JSON lines               " level: error / user.id: 1 / user.name: Ana ...
:JSON keys                " level / user.id / user.name -- just the paths
:JSON pretty 4             " 4-space indent instead of the default 2
'<,'>JSON compact          " only the visual selection, not the whole buffer
```

Without pasting anything first — straight from the clipboard, result in a
scratch split, current buffer untouched:

```
:JSON pretty --reg=+       " format what you copied out of the ticket tool
:JSON compact --out-reg=+  " minify this buffer back onto the clipboard
```

See [commands.md](commands.md) for every action and for the
[source/target flags](commands.md#source-and-target-flags), and
[what-you-get.md](what-you-get.md) for what's on by default with zero
configuration.
