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

See [commands.md](commands.md) for every action, and [what-you-get.md](what-you-get.md)
for what's on by default with zero configuration.
