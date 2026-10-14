| i |
i := 1.
[i <= 5] whileTrue: [
    Transcript show: 'value'; cr.
    i := i + 1.
].
^i
